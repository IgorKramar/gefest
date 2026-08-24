-- Сессии исполнителей и их журнал вех.

-- --------------------------------------------------------------------------
-- sessions
-- --------------------------------------------------------------------------
CREATE TABLE sessions (
    id bigserial PRIMARY KEY,
    uuid7 uuid NOT NULL UNIQUE,
    task_id bigint REFERENCES tasks(id),
    -- Роль-исполнитель. Она же субъект RLS: политика пускает актора к своим
    -- сессиям (миграция 0006).
    actor_id bigint NOT NULL REFERENCES actors(id),
    command_id bigint,
    cwd text,
    state text NOT NULL CHECK (state IN (
        'starting', 'running', 'interrupted', 'completed', 'failed'
    )),
    -- Идентификатор сессии со стороны CLI: по нему выполняется --resume.
    claude_session_id text,
    started_at timestamptz NOT NULL DEFAULT now(),
    ended_at timestamptz,
    -- Саммари пишет сам исполнитель в конце работы: приватность ADR-0003
    -- запрещает отдавать содержимое клиентских сессий фоновым LLM.
    summary text,
    -- Полнотекстовый поиск по саммари.
    --
    -- STORED пишется ЯВНО. В PG 18 дефолтный вид генерируемой колонки —
    -- VIRTUAL, и объявление без этого слова успешно создаёт таблицу, после
    -- чего CREATE INDEX ниже падает с «indexes on virtual generated columns
    -- are not supported». В forward-only серии это остановка без отката.
    --
    -- to_tsvector с ДВУМЯ аргументами обязателен: одноаргументная форма лишь
    -- STABLE, потому что зависит от default_text_search_config, и Postgres
    -- отвергает её в генерируемом выражении как не-IMMUTABLE.
    --
    -- Конфигурация russian покрывает и русский, и английский: словарная
    -- карта отправляет asciiword в english_stem, а word — в russian_stem.
    -- Отдельная конфигурация для смешанного текста не нужна.
    summary_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('russian', coalesce(summary, '')), 'A')
    ) STORED,
    -- Путь к сырому stream-json. Файл живёт вне БД и вне бэкапа (ADR-0005).
    raw_path text,
    raw_state text NOT NULL DEFAULT 'present'
        CHECK (raw_state IN ('present', 'rotated', 'failed')),
    usage jsonb,
    revision integer NOT NULL DEFAULT 0
);

COMMENT ON TABLE sessions IS
    'Сессии исполнителей. Под RLS: актор видит свои (миграция 0006).';
COMMENT ON COLUMN sessions.summary_tsv IS
    'FTS по саммари. STORED обязателен: в PG 18 дефолт VIRTUAL, а на него нельзя построить индекс.';
COMMENT ON COLUMN sessions.raw_state IS
    'present | rotated | failed — судьба файла сырья; failed ставится при ENOSPC.';

-- GIN с fastupdate = off: при одном операторе предсказуемая задержка чтения
-- важнее пропускной способности записи. С включённым fastupdate поиск до
-- сброса отложенного списка вынужден сканировать его целиком.
CREATE INDEX sessions_summary_tsv_gin ON sessions
    USING gin (summary_tsv) WITH (fastupdate = off);

-- Одна живая сессия на задачу. Частичный UNIQUE, а не полный: завершённых
-- сессий у задачи может быть сколько угодно.
CREATE UNIQUE INDEX sessions_one_running_per_task
    ON sessions (task_id)
    WHERE state = 'running' AND task_id IS NOT NULL;

CREATE INDEX sessions_actor_idx ON sessions (actor_id);

-- --------------------------------------------------------------------------
-- session_events — вехи, а не сырьё
-- --------------------------------------------------------------------------
-- Собственной колонки актора здесь нет намеренно: событие принадлежит
-- сессии, и видимость наследуется от неё. Политика RLS в 0006 написана
-- через подзапрос к sessions — родитель тоже под FORCE, поэтому цепочка
-- остаётся fail-closed.
CREATE TABLE session_events (
    id bigserial PRIMARY KEY,
    session_id bigint NOT NULL REFERENCES sessions(id),
    version integer NOT NULL,
    ts timestamptz NOT NULL DEFAULT now(),
    kind text NOT NULL CHECK (kind IN (
        'message', 'tool_call', 'tool_result', 'status', 'error', 'milestone'
    )),
    -- Веха с указателем в сырьё, не само сырьё: drill-down выполняется
    -- срезом raw-файла по смещениям (ADR-0008).
    payload jsonb NOT NULL,
    UNIQUE (session_id, version)
);

COMMENT ON TABLE session_events IS
    'Append-only вехи сессии. RLS наследуется от родительской сессии.';

CREATE TRIGGER session_events_append_only
    BEFORE UPDATE OR DELETE ON session_events
    FOR EACH ROW EXECUTE FUNCTION journal_is_append_only();

-- BRIN по возрастающему идентификатору с обязательным autosummarize:
-- без него непросуммированные диапазоны считаются подходящими под любое
-- условие, и деградирует запрос по старым данным, а не по новым.
CREATE INDEX session_events_id_brin ON session_events
    USING brin (id) WITH (autosummarize = on);

CREATE INDEX session_events_session_idx ON session_events (session_id, version);
