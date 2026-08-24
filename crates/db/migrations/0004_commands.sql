-- Команды и история их доставки.
--
-- Две оси — две таблицы (ADR-0005, анти-костыль №1 донора):
--   commands.execution_state — где команда в своём жизненном цикле;
--   command_deliveries       — append-only история попыток вручения.
-- У донора обе оси жили в одной колонке, из-за чего «доставлено» и
-- «выполнено» перезаписывали друг друга.

-- --------------------------------------------------------------------------
-- commands
-- --------------------------------------------------------------------------
CREATE TABLE commands (
    id bigserial PRIMARY KEY,
    uuid7 uuid NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    -- Обе стороны участвуют в RLS: политика 0006 пускает и автора, и
    -- адресата. Иначе раннер не увидел бы того, что обязан забрать, а
    -- владелец — того, что сам выдал.
    issued_by bigint NOT NULL REFERENCES actors(id),
    addressee_id bigint REFERENCES actors(id),
    -- Вид — ссылка на справочник, не свободная строка: произвольное
    -- значение здесь означало бы исполнение чужого намерения (RCE-защита).
    kind text NOT NULL REFERENCES command_kinds(code),
    task_id bigint REFERENCES tasks(id),
    session_id bigint REFERENCES sessions(id),
    payload jsonb,
    execution_state text NOT NULL DEFAULT 'issued' CHECK (execution_state IN (
        'issued', 'taken', 'done', 'failed', 'rejected'
    )),
    -- Момент захвата: основа lease. Команда, взятая и брошенная упавшим
    -- раннером, освобождается по таймауту, а не залипает навсегда.
    taken_at timestamptz,
    finished_at timestamptz,
    result text,
    revision integer NOT NULL DEFAULT 0
);

COMMENT ON TABLE commands IS
    'Команды владельца и системы. Под RLS: видят автор и адресат (0006).';
COMMENT ON COLUMN commands.execution_state IS
    'Ось исполнения. Ось доставки живёт отдельно, в command_deliveries.';
COMMENT ON COLUMN commands.taken_at IS
    'Момент захвата. Команда в taken старше 5 минут доступна повторному захвату.';

-- Живые команды — горячая выборка раннера: он опрашивает именно их.
CREATE INDEX commands_live_idx ON commands (execution_state, taken_at)
    WHERE execution_state IN ('issued', 'taken');

-- Идемпотентность: одна живая команда старта на задачу.
--
-- Предикат читается глазами благодаря текстовому PK справочника (0001).
-- С суррогатным ключом здесь стояло бы число, зависящее от порядка сева.
CREATE UNIQUE INDEX commands_one_live_start_per_task
    ON commands (task_id)
    WHERE kind = 'session_start'
      AND execution_state IN ('issued', 'taken')
      AND task_id IS NOT NULL;

-- --------------------------------------------------------------------------
-- command_deliveries — append-only история попыток
-- --------------------------------------------------------------------------
-- Текущий исход выводится последней записью, а не хранится колонкой:
-- история попыток и есть состояние доставки.
CREATE TABLE command_deliveries (
    id bigserial PRIMARY KEY,
    command_id bigint NOT NULL REFERENCES commands(id),
    ts timestamptz NOT NULL DEFAULT now(),
    outcome text NOT NULL CHECK (outcome IN (
        'sent', 'delivered', 'held', 'denied', 'expired', 'undeliverable'
    )),
    note text
);

COMMENT ON TABLE command_deliveries IS
    'Append-only история попыток вручения. Текущий исход = последняя запись.';
COMMENT ON COLUMN command_deliveries.outcome IS
    'delivered ставится по каузально связанной активности потока, не по факту записи (ADR-0007).';

CREATE TRIGGER command_deliveries_append_only
    BEFORE UPDATE OR DELETE ON command_deliveries
    FOR EACH ROW EXECUTE FUNCTION journal_is_append_only();

CREATE INDEX command_deliveries_id_brin ON command_deliveries
    USING brin (id) WITH (autosummarize = on);

CREATE INDEX command_deliveries_command_idx ON command_deliveries (command_id, ts DESC);
