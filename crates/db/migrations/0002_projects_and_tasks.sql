-- Проекты, счётчики ключей, задачи и их журнал.

-- --------------------------------------------------------------------------
-- projects
-- --------------------------------------------------------------------------
CREATE TABLE projects (
    id bigserial PRIMARY KEY,
    key text NOT NULL UNIQUE,
    title text NOT NULL,
    repo_url text,
    -- Признак приватности. NOT NULL и БЕЗ DEFAULT намеренно: класс проекта
    -- называется при заведении, а не доунаследуется молча.
    --
    -- На этой колонке держится fail-loud фильтр приватности ADR-0003 —
    -- признак, по которому клиентская сессия отличается от личной и не
    -- уходит в фоновые LLM-задачи. Сам фильтр приходит в Ф2, но колонка
    -- заводится сейчас: ретрофит потребовал бы ручной классификации
    -- накопленного, причём безопасный дефолт ('client') сломал бы всё, что
    -- к тому моменту на фильтр опирается, а удобный ('personal') молча
    -- раскрыл бы накопленное.
    scope_class text NOT NULL CHECK (scope_class IN ('personal', 'client')),
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE projects IS
    'Проекты. key иммутабелен: переименование меняет title, не ключ.';
COMMENT ON COLUMN projects.scope_class IS
    'personal | client — вход fail-loud фильтра приватности ADR-0003.';

-- Ключ проекта иммутабелен: он входит в ключи всех задач ('GF-5'), и его
-- смена означала бы переименование каждой задачи и каждой внешней ссылки.
CREATE FUNCTION projects_key_is_immutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.key IS DISTINCT FROM OLD.key THEN
        RAISE EXCEPTION 'projects.key иммутабелен: % -> %', OLD.key, NEW.key
            USING HINT = 'переименование проекта меняет title, а не key';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER projects_key_immutable
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION projects_key_is_immutable();

-- --------------------------------------------------------------------------
-- project_counters — источник порядковых номеров задач
-- --------------------------------------------------------------------------
CREATE TABLE project_counters (
    project_id bigint PRIMARY KEY REFERENCES projects(id) ON DELETE CASCADE,
    next_seq integer NOT NULL DEFAULT 1 CHECK (next_seq > 0)
);

COMMENT ON TABLE project_counters IS
    'Счётчик номеров задач проекта. Строку заводит триггер на projects.';

-- Строку счётчика заводит триггер, а не вызывающий код.
--
-- Без этого функция присвоения ключа получила бы ноль строк на первом же
-- проекте, созданном через API, — а тесты этого не поймали бы, потому что
-- готовят счётчик руками.
CREATE FUNCTION projects_init_counter() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO project_counters (project_id, next_seq) VALUES (NEW.id, 1);
    RETURN NEW;
END;
$$;

CREATE TRIGGER projects_counter_init
    AFTER INSERT ON projects
    FOR EACH ROW EXECUTE FUNCTION projects_init_counter();

-- --------------------------------------------------------------------------
-- tasks
-- --------------------------------------------------------------------------
CREATE TABLE tasks (
    id bigserial PRIMARY KEY,
    uuid7 uuid NOT NULL UNIQUE,
    project_id bigint NOT NULL REFERENCES projects(id),
    seq integer NOT NULL,
    -- Ключ хранимый, а не GENERATED: выражение GENERATED не может ссылаться
    -- на другую таблицу, а project.key живёт в projects (эскиз design §2
    -- правится поправкой 4 решения ред. 2).
    key text NOT NULL UNIQUE,
    title text NOT NULL,
    kind text NOT NULL DEFAULT 'task' CHECK (kind IN ('task', 'epic')),
    -- Дверь эпиков: колонка есть, иерархия не используется до D-15.
    parent_id bigint REFERENCES tasks(id),
    status text NOT NULL REFERENCES task_statuses(code),
    assignee_id bigint REFERENCES actors(id),
    created_by bigint NOT NULL REFERENCES actors(id),
    -- CAS: каждое изменение состояния проверяет и продвигает revision.
    revision integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (project_id, seq)
);

COMMENT ON TABLE tasks IS
    'Задачи. Ключ вида GF-5 присваивается функцией next_task_key при вставке.';
COMMENT ON COLUMN tasks.revision IS
    'Счётчик CAS: UPDATE ... WHERE revision = $n; версия события = revision + 1.';

-- Присвоение ключа: блокировка счётчика, инкремент, сборка кода.
--
-- FOR UPDATE держит строку счётчика до конца транзакции, поэтому две
-- одновременные вставки в один проект получают разные номера — вторая ждёт
-- первую.
CREATE FUNCTION next_task_key(p_project_id bigint, OUT out_seq integer, OUT out_key text)
LANGUAGE plpgsql AS $$
DECLARE
    v_project_key text;
BEGIN
    SELECT next_seq INTO out_seq
        FROM project_counters
        WHERE project_id = p_project_id
        FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'нет счётчика для проекта %', p_project_id
            USING HINT = 'строку заводит триггер projects_counter_init';
    END IF;

    UPDATE project_counters
        SET next_seq = next_seq + 1
        WHERE project_id = p_project_id;

    SELECT key INTO v_project_key FROM projects WHERE id = p_project_id;
    out_key := v_project_key || '-' || out_seq;
END;
$$;

COMMENT ON FUNCTION next_task_key(bigint) IS
    'Выдаёт следующий номер и ключ задачи под блокировкой счётчика проекта.';

-- Заполнение seq и key при вставке, если вызывающий их не задал.
CREATE FUNCTION tasks_assign_key() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_seq integer;
    v_key text;
BEGIN
    IF NEW.seq IS NULL OR NEW.key IS NULL THEN
        SELECT out_seq, out_key INTO v_seq, v_key FROM next_task_key(NEW.project_id);
        NEW.seq := COALESCE(NEW.seq, v_seq);
        NEW.key := COALESCE(NEW.key, v_key);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER tasks_key_assign
    BEFORE INSERT ON tasks
    FOR EACH ROW EXECUTE FUNCTION tasks_assign_key();

-- --------------------------------------------------------------------------
-- task_events — append-only журнал задач
-- --------------------------------------------------------------------------
CREATE TABLE task_events (
    id bigserial PRIMARY KEY,
    task_id bigint NOT NULL REFERENCES tasks(id),
    -- Версия события: revision состояния + 1, обе пишутся одной транзакцией.
    version integer NOT NULL,
    ts timestamptz NOT NULL DEFAULT now(),
    actor_id bigint NOT NULL REFERENCES actors(id),
    kind text NOT NULL CHECK (kind IN (
        'created', 'status', 'assignee', 'note', 'imported', 'estimate'
    )),
    -- Trust-дверь D-16: agent_external помечает действие, инициированное
    -- недоверенным содержимым. Заполняется раннером по эвристике источника.
    origin text NOT NULL CHECK (origin IN ('owner', 'agent', 'agent_external')),
    from_value text,
    to_value text,
    note text,
    UNIQUE (task_id, version)
);

COMMENT ON TABLE task_events IS
    'Append-only журнал задач. Единственный путь внешних импортов — kind = imported.';
COMMENT ON COLUMN task_events.origin IS
    'Trust-класс действия; дверь D-16. Зеркало hef_core::EventOrigin.';

-- Запрет изменения журнала. Первая линия — привилегии (UPDATE/DELETE не
-- выдаются роли приложения), эта — вторая, на случай ошибки в GRANT.
CREATE FUNCTION journal_is_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'таблица % — append-only, % запрещён',
        TG_TABLE_NAME, TG_OP
        USING HINT = 'исправление вносится корректирующим событием, а не правкой истории';
END;
$$;

COMMENT ON FUNCTION journal_is_append_only() IS
    'Запрет UPDATE/DELETE на журнальных таблицах: история не переписывается.';

-- ВАЖНО для тестов: триггер FOR EACH ROW не вызывается, когда строк нет.
-- UPDATE или DELETE по пустой журнальной таблице проходит без ошибки, и
-- проверка запрета на пустой таблице ничего не проверяет. Тесты обязаны
-- сначала вставить строку — иначе они тихо вырождаются.

CREATE TRIGGER task_events_append_only
    BEFORE UPDATE OR DELETE ON task_events
    FOR EACH ROW EXECUTE FUNCTION journal_is_append_only();

-- BRIN по возрастающему идентификатору: журнал физически упорядочен по
-- вставке, и диапазонные сканы дешевле btree на порядки (32 кБ против 64 МБ
-- на журнале в 3.4 млн строк).
--
-- autosummarize = on обязателен и НЕ является умолчанием. Без него
-- непросуммированные диапазоны BRIN обязан считать подходящими под любое
-- условие, и запрос по СТАРЫМ данным деградирует после свежих вставок:
-- замерено 256 блоков против 6851 после 500 тысяч непросуммированных строк.
-- Автовакуум приходит к append-only таблице неохотно.
CREATE INDEX task_events_id_brin ON task_events
    USING brin (id) WITH (autosummarize = on);

CREATE INDEX task_events_task_id_idx ON task_events (task_id, version);
