-- Права ролей и построчная защита ядра доставки.
--
-- Порядок внутри файла обязателен: права → политики → ENABLE → FORCE.
-- Политика без ENABLE неактивна, ENABLE без политики отсекает всё; оба
-- промежуточных состояния безопасны внутри одной транзакции, но порядок
-- фиксируется, чтобы его не выбирали заново на каждой следующей таблице.

-- --------------------------------------------------------------------------
-- Отзыв умолчаний
-- --------------------------------------------------------------------------
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO gefest_app, gefest_owner;

-- --------------------------------------------------------------------------
-- Права роли приложения — поимённо, без GRANT ALL
-- --------------------------------------------------------------------------
-- GRANT ALL дал бы TRUNCATE, а он не вызывает построчных триггеров и не
-- подчиняется политикам RLS: одной строкой роль приложения получила бы
-- возможность стереть журналы и сам аудит дочиста, мимо обеих защит,
-- которые эта схема выстраивает конструкциями. Проверено на PG 18.

-- State-таблицы: читает, создаёт, обновляет.
GRANT SELECT, INSERT, UPDATE ON tasks, sessions, commands TO gefest_app;

-- Журнальные: читает и дописывает. UPDATE и DELETE не выдаются — запрет
-- триггером остаётся второй линией, а не единственной.
GRANT SELECT, INSERT ON task_events, session_events, command_deliveries TO gefest_app;

-- Справочники: только чтение.
GRANT SELECT ON command_kinds, task_statuses TO gefest_app;

-- Проекты и участники: чтение и заведение.
GRANT SELECT, INSERT ON projects, actors TO gefest_app;
GRANT SELECT, UPDATE ON project_counters TO gefest_app;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO gefest_app;

-- INSERT на audit_log роли приложения НЕ выдаётся: пишет функция
-- audit_row() с правами владельца. Роль не может ни подделать запись, ни
-- удалить её.

-- --------------------------------------------------------------------------
-- Права отладочной роли владельца
-- --------------------------------------------------------------------------
-- gefest_owner читает всё, но не пишет и не владеет объектами. Роль
-- существует для разбора в консоли; без явного объёма политики она видела
-- бы ноль строк под FORCE, и первая же отладка чинила бы это самой широкой
-- политикой из возможных — навсегда.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO gefest_owner;

-- --------------------------------------------------------------------------
-- Политики
-- --------------------------------------------------------------------------
-- Предикат берёт контекст через nullif(..., ''), а НЕ через IS NULL.
--
-- current_setting('app.actor_id', true) возвращает NULL только до первого
-- касания GUC на этом соединении; после — пустую строку, и DISCARD ALL
-- этого не отменяет. Политика, охраняющая через IS NULL, работает на первом
-- запросе каждого соединения и тихо перестаёт охранять на всех следующих.
--
-- Обёртка (SELECT ...) даёт InitPlan-кеширование: значение вычисляется раз
-- на запрос, а не на строку.

-- sessions: актор видит свои сессии.
CREATE POLICY sessions_own_actor ON sessions
    FOR ALL TO gefest_app
    USING (actor_id = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint)
    WITH CHECK (actor_id = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint);

-- session_events: собственной колонки актора нет — видимость наследуется
-- от родительской сессии. Родитель тоже под FORCE, поэтому цепочка
-- остаётся fail-closed.
CREATE POLICY session_events_via_parent ON session_events
    FOR ALL TO gefest_app
    USING (EXISTS (
        SELECT 1 FROM sessions s
        WHERE s.id = session_events.session_id
          AND s.actor_id = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM sessions s
        WHERE s.id = session_events.session_id
          AND s.actor_id = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint
    ));

-- commands: команду видят ОБЕ стороны — автор и адресат.
--
-- Это решение, а не расширение по ходу дела: с предикатом только по автору
-- раннер не увидел бы того, что обязан забрать, а с предикатом только по
-- адресату владелец не увидел бы того, что сам выдал. При открытии
-- trust-двери D-16, когда у агентов появятся собственные акторы, предикат
-- придётся пересматривать вместе с политиками на tasks.
CREATE POLICY commands_issuer_or_addressee ON commands
    FOR ALL TO gefest_app
    USING (
        issued_by = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint
        OR addressee_id = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint
    )
    WITH CHECK (
        issued_by = (SELECT nullif(current_setting('app.actor_id', true), ''))::bigint
    );

-- Отладочный контур владельца: видит всё, объём назван явно.
CREATE POLICY sessions_owner_read ON sessions
    FOR SELECT TO gefest_owner USING (true);
CREATE POLICY session_events_owner_read ON session_events
    FOR SELECT TO gefest_owner USING (true);
CREATE POLICY commands_owner_read ON commands
    FOR SELECT TO gefest_owner USING (true);

-- --------------------------------------------------------------------------
-- Включение
-- --------------------------------------------------------------------------
-- FORCE применяется и к владельцу таблиц — в этом весь смысл: gefest_app и
-- gefest_owner не владельцы, но владелец без FORCE обходил бы политики.
--
-- Следствие, которое обязано быть известно заранее: после FORCE любой
-- UPDATE или DELETE от владельца без actor-контекста возвращает НОЛЬ строк
-- и НЕ падает — миграция коммитится, ничего не изменив. Поэтому всякая
-- будущая запись в эти таблицы мимо прослойки (волна 2, партиционирование,
-- janitor с retention) обязана нести либо ALTER TABLE ... NO FORCE в начале
-- файла с возвратом FORCE в конце, либо set_config('app.actor_id', ..., true)
-- в самой миграции. Это сторожится scripts/guard-set-config.sh.
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE commands ENABLE ROW LEVEL SECURITY;

ALTER TABLE sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE session_events FORCE ROW LEVEL SECURITY;
ALTER TABLE commands FORCE ROW LEVEL SECURITY;

-- tasks и projects под RLS НЕ ставятся (расхождение с поправкой CC-7
-- решения ред. 2, зафиксировано в Review trail ADR-0005).
--
-- Разделяющий критерий: политика держится там, куда раннер пишет от имени
-- актора. У sessions, session_events и commands есть актор-владелец строки;
-- у tasks его нет, и политика при одном операторе стерегла бы не участника,
-- а баг в собственном API. Возврат обойдётся дороже одной миграции: колонка
-- актора с заполнением истории из task_events плюс ревизия всех путей
-- чтения, написанных к тому моменту без контекста.
