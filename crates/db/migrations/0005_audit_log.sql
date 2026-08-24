-- Журнал аудита: факт записи мимо приложения.
--
-- Смысл контроля — поймать изменение, пришедшее не через API Гефеста
-- (владелец в psql, ошибка в скрипте). Поэтому писать его приложением
-- нельзя: аудит стал бы дочерним тому самому пути, обход которого он
-- фиксирует. Пишет триггерная функция от имени владельца объектов.

CREATE TABLE audit_log (
    id bigserial PRIMARY KEY,
    ts timestamptz NOT NULL DEFAULT now(),
    -- Кто: роль подключения и actor-контекст, если он был выставлен.
    db_role text NOT NULL,
    app_actor_id bigint,
    -- Что: таблица и первичный ключ строки. Без old/new намеренно —
    -- копия данных в аудите удваивает поверхность утечки, а вопрос
    -- «что именно изменилось» решается журналом событий домена.
    table_name text NOT NULL,
    row_pk bigint NOT NULL,
    operation text NOT NULL CHECK (operation IN ('UPDATE', 'DELETE'))
);

COMMENT ON TABLE audit_log IS
    'Факт записи мимо приложения. Без old/new: не плодим копии данных. Retention 12 месяцев.';
COMMENT ON COLUMN audit_log.app_actor_id IS
    'NULL означает запись вообще без actor-контекста — самый интересный случай.';

CREATE TRIGGER audit_log_append_only
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION journal_is_append_only();

CREATE INDEX audit_log_ts_brin ON audit_log
    USING brin (ts) WITH (autosummarize = on);

-- --------------------------------------------------------------------------
-- Писатель аудита
-- --------------------------------------------------------------------------
-- SECURITY DEFINER: функция выполняется с правами владельца объектов, а не
-- вызывающего. Благодаря этому роль приложения не нуждается в INSERT на
-- audit_log — и, соответственно, не может подделать или удалить запись.
--
-- search_path фиксируется явно: без этого функция с правами владельца —
-- классическая точка перехвата через подменённые объекты в чужой схеме.
CREATE FUNCTION audit_row() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_actor text := nullif(current_setting('app.actor_id', true), '');
    v_pk bigint;
BEGIN
    -- session_user, а НЕ current_user.
    --
    -- Внутри SECURITY DEFINER-функции current_user — это владелец функции
    -- (gefest_migrator), а не вызывающая роль. Сравнение current_user с
    -- 'gefest_app' не совпадает никогда: проверено — штатный поток от роли
    -- приложения с контекстом записывал строки аудита, а db_role в них
    -- показывал мигратора вместо реального подключения.
    --
    -- session_user отдаёт роль, под которой открыта сессия, — то есть того,
    -- кто действительно выполняет запись.
    IF session_user = 'gefest_app' AND v_actor IS NOT NULL THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    v_pk := COALESCE(NEW.id, OLD.id);

    INSERT INTO audit_log (db_role, app_actor_id, table_name, row_pk, operation)
    VALUES (session_user, v_actor::bigint, TG_TABLE_NAME, v_pk, TG_OP);

    RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION audit_row() IS
    'Пишет audit_log при изменении state-таблицы мимо роли приложения или без actor-контекста.';

-- Навешивается на state-таблицы: их правка мимо приложения и есть то, что
-- контроль обязан замечать. Журнальные таблицы не нужны — они защищены
-- запретом UPDATE/DELETE целиком.
CREATE TRIGGER tasks_audit
    AFTER UPDATE OR DELETE ON tasks
    FOR EACH ROW EXECUTE FUNCTION audit_row();

CREATE TRIGGER sessions_audit
    AFTER UPDATE OR DELETE ON sessions
    FOR EACH ROW EXECUTE FUNCTION audit_row();

CREATE TRIGGER commands_audit
    AFTER UPDATE OR DELETE ON commands
    FOR EACH ROW EXECUTE FUNCTION audit_row();
