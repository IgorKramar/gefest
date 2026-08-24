-- Справочники-зеркала и участники.
--
-- Истина перечислений — Rust-enum в hef-core (ADR-0005). Эти таблицы их
-- зеркалят и наполняются ТОЛЬКО миграциями: runtime-INSERT запрещён
-- триггером ниже. Расхождение между кодом и базой ловит тест синхронизации.

-- --------------------------------------------------------------------------
-- Общий запрет наполнения справочников в рантайме
-- --------------------------------------------------------------------------
-- Функция навешивается на каждую lookup-таблицу. Миграции обходят её тем,
-- что выполняются до навешивания триггера, — порядок внутри файла важен.
CREATE FUNCTION lookup_is_migration_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION
        'таблица % — зеркало Rust-enum, наполняется только миграциями',
        TG_TABLE_NAME
        USING HINT = 'добавьте вариант в hef-core::enums и напишите миграцию';
END;
$$;

COMMENT ON FUNCTION lookup_is_migration_only() IS
    'Запрет runtime-записи в справочники: истина перечислений — Rust-enum.';

-- --------------------------------------------------------------------------
-- command_kinds — виды команд
-- --------------------------------------------------------------------------
-- Первичный ключ текстовый, а не bigserial. Это намеренное исключение из
-- правила «bigserial PK» (ADR-0005 R13), и вот почему: предикат частичного
-- уникального индекса обязан быть IMMUTABLE, поэтому идемпотентность
-- «одна живая команда старта на задачу» вынуждена называть вид команды
-- литералом. С суррогатным ключом этот литерал был бы числом, зависящим от
-- порядка сева строк ниже, — и правка порядка INSERT-ов молча меняла бы
-- смысл индекса. С текстовым кодом предикат читается глазами.
CREATE TABLE command_kinds (
    code text PRIMARY KEY,
    description text NOT NULL
);

COMMENT ON TABLE command_kinds IS
    'Виды команд. Зеркало hef_core::CommandKind; PK текстовый ради читаемых предикатов частичных индексов.';

INSERT INTO command_kinds (code, description) VALUES
    ('session_start', 'Запустить сессию исполнителя по задаче'),
    ('session_stop',  'Остановить живую сессию'),
    ('instruction',   'Доставить указание в stdin работающей сессии'),
    ('answer',        'Ответ владельца на вопрос агента');

CREATE TRIGGER command_kinds_migration_only
    BEFORE INSERT OR UPDATE OR DELETE ON command_kinds
    FOR EACH ROW EXECUTE FUNCTION lookup_is_migration_only();

-- --------------------------------------------------------------------------
-- task_statuses — статусы задач
-- --------------------------------------------------------------------------
-- Lookup вместо CHECK: статусы расширяются без DROP CONSTRAINT
-- (ADR-0005, анти-костыль №4 донора).
CREATE TABLE task_statuses (
    code text PRIMARY KEY,
    is_terminal boolean NOT NULL,
    description text NOT NULL
);

COMMENT ON TABLE task_statuses IS
    'Статусы задач. Зеркало hef_core::TaskStatus; is_terminal зеркалит одноимённый метод.';

INSERT INTO task_statuses (code, is_terminal, description) VALUES
    ('backlog',     false, 'Заведена, не начата'),
    ('in_progress', false, 'В работе'),
    ('waiting',     false, 'Ждёт ответа или внешнего события'),
    ('done',        true,  'Завершена'),
    ('cancelled',   true,  'Отменена');

CREATE TRIGGER task_statuses_migration_only
    BEFORE INSERT OR UPDATE OR DELETE ON task_statuses
    FOR EACH ROW EXECUTE FUNCTION lookup_is_migration_only();

-- --------------------------------------------------------------------------
-- actors — люди и роли в одной таблице
-- --------------------------------------------------------------------------
-- Автор и адресат везде ссылаются сюда. Владелец, роли-исполнители и
-- системные акторы различаются полем kind, а не отдельными таблицами:
-- FK из десятка мест на одну таблицу проще, чем полиморфная ссылка.
CREATE TABLE actors (
    id bigserial PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('owner', 'role', 'system')),
    name text NOT NULL UNIQUE,
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE actors IS
    'Участники: владелец, роли-исполнители, системные акторы. Цель FK для автора и адресата.';
COMMENT ON COLUMN actors.kind IS
    'owner — человек; role — агент-исполнитель; system — сам Гефест (reconciliation, janitor).';
