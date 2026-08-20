# Research digest: схема данных Гефеста (D-2)

Дата: 2026-08-20. Два источника: (1) полный DDL-разбор донора agent-dashboard (агент-исследователь, 13 SQL-файлов + read-path кода); (2) веб-дайджест Postgres-паттернов (агент-исследователь, август 2026).

## Question

Как устроить схему: event sourcing или журнал+state; пуш в SSE; журналы и retention; RLS с одним пулом sqlx; FTS для русско-английского; миграции; PK.

## Headline finding

Консенсус для малой системы: **«журнал + материализованное состояние» вместо полного ES**; NOTIFY — будильник поверх поллинга с курсором, не транспорт; BRIN + batched DELETE вместо партиционирования (двери оставить); RLS через `set_config(..., true)` строго в транзакции (+ `FORCE ROW LEVEL SECURITY` — владелец обходит политики!); штатная FTS-конфигурация `russian` уже стеммит и английские токены (`asciiword → english_stem`); sqlx migrate зрел (чек-суммы, embedded, forward-only); PK — bigserial внутри + бизнес-ключ снаружи, UUIDv7 приложением только где ID уходит наружу (нативный `uuidv7()` — лишь PG18).

## Detailed findings

### Донор agent-dashboard: 10 паттернов забрать
Append-only событие + вывод состояния с принуждением правами (у агента нет UPDATE на tasks; SECURITY DEFINER-триггер — единственный путь); **перечисление вместо строки к исполнению** (защита от RCE); CAS-захват `WHERE state='issued'` + rowcount; частичный индекс под очередь `WHERE state IN (...)`; разделение заявленного (tasks) и наблюдаемого (observations); исходы вместо фактов (`answered/faded/lifted`; `sent≠delivered`); синглтон-таблица `only_row`; снимок проекции одной транзакцией; `file_digest` как отпечаток выгруженного; комментарий-в-DDL как носитель причины.

### Донор agent-dashboard: 16 костылей не тащить (главные)
Две ортогональные оси в одной колонке `commands.state` (доставка стирает исполнение и выносит команду из очереди); `path`/`name` как PK (+CASCADE = потеря истории при переименовании) → суррогатный PK + UNIQUE; триггер без защиты от порядка (`WHERE updated_at <= NEW.ts` отсутствует — бэкфилл откатывает состояние); **два пути записи в tasks** (коллектор пишет мимо событий); пароли ролей в миграциях; `sorted(glob)` без чек-сумм; расширение CHECK через DROP+ADD (окно без проверки) → enum-тип или lookup-таблица; `blocked_by text[]` без FK → таблица зависимостей; табличный UPDATE агенту на commands (может переписать чужое) → колоночные гранты + авторство; FTS без хранимого tsvector/весов; `observations` через DELETE+INSERT каждый цикл; дрейф констант SQL↔приложение (в Rust лечится `sqlx::Type`-enum); ревизии без защиты от дублей.

### Веб: event sourcing
Полный ES избыточен для малых систем (консенсус, вкл. Azure Architecture Center). Середина: append-only журнал + state-таблицы, **обновляемые в той же транзакции приложением** (логика тестируется как Rust-код); триггеры — для инвариантов (запрет UPDATE/DELETE на журналах). Sequence per stream `(stream_id, version)` UNIQUE — gapless внутри стрима, optimistic concurrency. Глобальный bigserial имеет дыры и **commit out-of-order** — читатель по курсору может пропустить событие; для нашего масштаба лечится «один писатель на стрим» (раннер владеет сессией) + ожидание пропуска с таймаутом. Idempotent consumers: `consumer_offsets`.

### Веб: LISTEN/NOTIFY
Payload ≤ 8000, потеря при disconnect без индикации (в т.ч. дыра PgListener между reconnect и re-subscribe — обязателен re-read состояния). Паттерн: **NOTIFY — будильник, поллинг с курсором — истина**; пустой payload. PgListener sqlx зрел (фиксы 2025), выделенное соединение.

### Веб: журналы
BRIN по `created_at`/монотонному PK — дефолтный индекс append-only (~1/100 btree); партиционирование — только когда retention-DELETE заболит (десятки ГБ); **ключ партиционирования включить в PK заранее**, чтобы навесить позже без смены PK. pg_partman совместим, но избыточен.

### Веб: RLS
`BEGIN; SELECT set_config('app.actor', $1, true); ...` (`SET LOCAL` не биндится — utility statement; `set_config` биндится). Грабли: обычный `SET` утекает следующему из пула; **владелец таблиц обходит RLS без `FORCE ROW LEVEL SECURITY`** (приложение почти всегда коннектится владельцем!); `current_setting()` на каждую строку → обёртка `(SELECT current_setting(...))` для InitPlan-кеширования; SECURITY DEFINER обходит RLS (фича и дыра: `SET search_path = ''` внутри обязателен). Statement-пулеры несовместимы (у нас чистый sqlx-пул — ок).

### Веб: FTS
Конфигурация `russian` из коробки: `asciiword → english_stem`, кириллица → `russian_stem` — одна колонка покрывает смешанный текст. Хранимый `tsvector GENERATED ALWAYS AS (setweight(to_tsvector('russian', title),'A') || setweight(..., 'B')) STORED` + GIN; **явный regconfig обязателен** (immutability). `unaccent` не immutable — не тащить в GENERATED. pg_trgm — дополнение для идентификаторов/опечаток.

### Веб: миграции и PK
sqlx migrate: `_sqlx_migrations` с чек-суммами, `sqlx::migrate!()` embedded в бинарь, forward-only — брать штатный. PK: bigserial внутри (8 байт, каскадно в FK); UUIDv7 приложением (`uuid` crate, v7) — только для ID, уходящих наружу; бизнес-ключи (`GF-7`) — UNIQUE-колонкой, не PK.

## Caveats and unknowns

PgListener в sqlx 0.9 после PR #4016 — прогнать smoke-тест reconnect; immutability unaccent — проверить на месте; ru+en FTS — прогнать `ts_debug` на своём корпусе терминов; event-sourcing-источники в основном 2019–2023 (стабильность паттерна, не устарелость).

## Implications for the design phase

Гибрид «журнал + state в одной транзакции» — научно обоснованная середина (вопрос №2 владельца); commands разъезжается на две оси (исполнение/доставка) или две таблицы; RLS-паттерн `set_config` + `FORCE` — конкретен; FTS-схема готова; NOTIFY-будильник + курсор — модель SSE; BRIN + retention с дверью в партиционирование; идентификаторы: bigserial + бизнес-ключ + UUIDv7 наружу.

## Sources

Веб (полный список с датами — в отчёте исследователя, ключевые): kspeakman dev.to Event Storage in Postgres; event-driven.io ordering_in_postgres_outbox; softwaremill event-sourcing part 3; github.com/eugene-khyst/postgresql-event-sourcing; learn.microsoft.com Event Sourcing Pattern; docs.rs sqlx PgListener + PR #3585/#4016; blog.sequinstream.com CDC in Postgres; crunchydata.com BRIN; sqlpassion.at BRIN (2026-01); patotski.com RLS footguns; scottpierce.dev Optimizing RLS; bytebase.com RLS footguns; postgresql.org ddl-rowsecurity + textsearch-controls; sqlx 0.9.0 discussion #4271; pganalyze UUID vs Serial; supabase Choosing a PK; habr UUIDv7 (2025). Донор: `/home/ikramar/projects/agent-dashboard/sql/001…013` + `dashboard/{commands,documents,journal,entities,db,runner,app,panel}.py`.
