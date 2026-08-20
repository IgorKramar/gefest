# Design: схема данных Гефеста (D-2) — альтернативы

- Дата: 2026-08-20 · Фаза: Design (deep) · Входы: discovery (2 раунда, C-Д1…C-Д4), research (донор DDL + веб-паттерны), ADR-0001…0004

## 1. Проблема и силы

Фундамент всех дальнейших решений. Силы: F-С1 (ES против читаемости), F-С2 (объём диалогов; C-С1 — байты = деньги), F-С3 (единая модель скоупов с памятью ADR-0003), F-С4/C-Д2 (RLS с v1), F-С5 (SSE-пуш), F-С6 (миграции в бинаре); инварианты §3 discovery (автор/адресат, append-only, идемпотентность, CAS, бюджеты, перечисления-не-строки).

**Общее для всех альтернатив — граница доступа (новое относительно донора):** агенты НЕ получают прямых подключений к БД (в AD CLI ходил в Postgres под ролью). Все пути агентов — через API Гефеста (MCP/CLI → бинарь). Роли Postgres остаются на два контура: `gefest_app` (бинарь) и `gefest_owner` (psql владельца), обе НЕ владельцы таблиц (иначе RLS обходится; отдельный `gefest_migrator` — владелец, только для миграций). Принуждение «агент не может X» переезжает с грантов БД на API-слой + RLS-политики по `set_config('app.actor', ...)`.

---

## 2. Альтернатива A — «Журнал + материализованное состояние» (гибрид)

**Одной строкой:** каждая машина состояний = append-only поток событий `(stream, version)` + state-таблица, обновляемые **в одной транзакции приложением**; триггеры — только инварианты (запрет UPDATE/DELETE журналов, защита порядка); панель читает state, история и replay — из событий.

### Эскиз схемы (домены → таблицы, ключевые колонки)

**identity/скоупы:**
- `actors(id bigserial PK, kind CHECK(owner|role|system), name UNIQUE, active)` — люди и роли в одной таблице (автор/адресат везде FK сюда).
- `roles_profile(actor_id PK→actors, specialization, character text, backstory text, prompt_config jsonb, provider, model)` — kst-профиль (C-Д4).
- `projects(id PK, key UNIQUE ('GF','ERP'), title, repo_url, scope_class CHECK(personal|client))` — `scope_class` питает приватность ADR-0003 и RLS.

**задачи (двери Jira — C-Д3, полная модель — D-15):**
- `tasks(id PK, project_id FK, seq int, key GENERATED (project.key||'-'||seq) UNIQUE, title, kind CHECK(task|epic), parent_id FK tasks NULL /*эпик-дверь*/, status FK task_statuses, column_id FK board_columns NULL /*человек ≠ машина*/, assignee_id FK actors NULL, priority FK, revision int /*CAS*/, created_by FK actors, updated_at)`; `project_counters(project_id PK, next_seq)`.
- `task_events(id bigserial PK, task_id FK, version int, UNIQUE(task_id,version), ts, actor_id FK, kind CHECK(created|status|assignee|column|note|imported|estimate|tagged), from_value, to_value, note)` — append-only (триггер-запрет UPDATE/DELETE); состояние пишется в той же транзакции; `imported` — единственный путь для внешних импортов (анти-костыль №8 донора).
- `task_dependencies(task_id, blocks_id, PK(...)), task_tags(task_id, tag_id), tags(id, name UNIQUE, color)`; `pools(id, name, kind CHECK(day|sprint), starts_on, ends_on)` + `pool_tasks(pool_id, task_id)` — дверь «на сегодня».
- `task_statuses(id, key UNIQUE, is_terminal)` — lookup-таблица вместо CHECK (расширяемо без DROP CONSTRAINT; анти-костыль №4).
- `boards(id, project_id, name)`, `board_columns(id, board_id, name, position)` — колонки = данные (yao-урок).

**команды и доставка (две оси = две таблицы; анти-костыль №1):**
- `commands(id PK, uuid7 UNIQUE /*наружу*/, created_at, issued_by FK actors, addressee_id FK actors NULL, kind FK command_kinds /*перечисление, не строка — RCE-защита*/, task_id FK NULL, payload jsonb, execution_state CHECK(issued|taken|done|failed|rejected), taken_at, finished_at, result, session_id FK NULL, revision int)`; частичный индекс `WHERE execution_state IN ('issued','taken')`; CAS-захват `UPDATE ... WHERE id=$1 AND execution_state='issued'`.
- `command_deliveries(id bigserial PK, command_id FK, ts, outcome CHECK(sent|delivered|held|denied|expired|undeliverable), note)` — append-only история попыток; «текущий исход» = последняя запись (view).
- Идемпотентность: `UNIQUE (task_id) WHERE execution_state IN ('issued','taken') AND kind='start'` — одна живая команда старта на задачу; аналогичный частичный UNIQUE на `sessions(task_id) WHERE state='running'`.

**сессии (C-Д1):**
- `sessions(id PK, uuid7 UNIQUE, task_id FK NULL, actor_id FK /*роль*/, command_id FK NULL, cwd, state CHECK(starting|running|interrupted|completed|failed), claude_session_id text, started_at, ended_at, summary text NULL /*пишет исполнитель в конце*/, summary_tsv GENERATED, raw_path text /*файл stream-json с ротацией*/, usage jsonb)`.
- `session_events(id bigserial, session_id FK, version int UNIQUE(session_id,version), ts, kind CHECK(message|tool_call|tool_result|status|error|milestone), payload jsonb /*веха, не сырьё*/)`; BRIN по id; retention DELETE батчами; PK включает ключ будущего партиционирования.
- Один писатель на стрим — раннер (лечит commit out-of-order).

**наблюдения и журнал:**
- `observations(id bigserial, seen_at, kind CHECK(worktree|session|merge|pr|ci), project_id FK NULL, task_id FK NULL, source CHECK(github|gitlab|fs), external_key text, payload jsonb, UNIQUE(kind,source,external_key))` — честный upsert по ключу вместо DELETE+INSERT (анти-костыль №9).
- `journal(id bigserial PK, ts, author_id FK actors, addressee_id FK actors NULL, task_id FK NULL, kind CHECK(question|block|close|answer|note), ref_id FK journal NULL, block_class, outcome, body)` + CHECK-и целостности, которых не было у донора: `(kind='close') = (ref_id IS NOT NULL)`, `UNIQUE(ref_id) WHERE kind='close'`, `(outcome IS NULL) OR kind='close'`.

**канон памяти (ADR-0003, дословно в DDL):**
- `memory_entries(id PK, uuid7, class FK memory_classes(карточка|журнал|правило|ловушка|learning|справочник), scope_kind CHECK(global|project|role), scope_project_id FK NULL, scope_actor_id FK NULL, layer CHECK(core|body), rank_weight real, title, body, search_tsv GENERATED(setweight A/B) STORED + GIN, revision int, author_id, updated_at, deleted_at NULL)`.
- `memory_revisions(entry_id FK, revision, ts, actor_id, body, reason, UNIQUE(entry_id, revision))`; `memory_links(from_id, to_id, kind)` — wiki/бэклинки.
- `memory_candidates(id, proposed_at, source_session_id FK NULL, source_kind, raw_body text /*копия сырья!*/, suggested_class, status CHECK(proposed|accepted|rejected|edited), decided_by, decided_at, entry_id FK NULL)`.
- `memory_embeddings(entry_id FK, model text, dim int, vector vector NULL, PK(entry_id, model))` — дверь; `recall_log(id bigserial, ts, actor_id, query text, result_ids bigint[], result_count int, miss bool)` — метаданные, BRIN, retention 6 мес.
- Бюджеты ядра/индекса — SQL-проверка в генераторе + CI-тест (не триггер на каждую запись: бюджет — свойство суммы, не строки).

**служебное:** `consumer_offsets(consumer PK, last_id)`; `collector_health`-синглтон; `exports_log`; `_sqlx_migrations`.

**RLS (C-Д2):** включена + `FORCE` на: memory_* (скоупы/классы — политики видимости из ADR-0003), sessions/session_events (клиентские скоупы), journal (адресат), commands (авторство изменений). Паттерн: `set_config('app.actor_id',$1,true)` + `set_config('app.scope',...)`; политики через `(SELECT current_setting(...))`. Оперативные projects/tasks — RLS-политики «все свои» (один владелец), но каркас единый — второй оператор добавляется политикой, не миграцией схемы.

**SSE:** NOTIFY-триггеры на журнальных таблицах с пустым payload («будильник»), SSE-хендлеры держат курсор по `consumer_offsets`.

### Как отвечает силам
F-С1 — читаемое состояние таблицей И полная история потоком, транзакция гарантирует согласованность (не eventual); F-С2 — вехи+саммари в БД, сырьё файлами (C-Д1); F-С3 — скоупы памяти и проектов из одного словаря; C-Д2 — RLS каркасом; F-С5 — будильник+курсор; инварианты — все закрыты конструкциями (см. эскиз).

### Легче / тяжелее / усилия / где ломается
Легче: отладка (state виден psql), панель без проекционных лагов, Rust-код обычный (INSERT event + UPDATE state в транзакции — одна функция на переход). Тяжелее: дисциплина «каждый переход — через событие» держится на API-слое (в БД — триггер-запреты UPDATE state-таблиц мимо приложенческих функций? — нет: держится на том, что писатель один — бинарь; для psql-владельца — политика «руками не писать» + аудит-триггер на прямые UPDATE). Усилия: ~30 таблиц, 8–12 миграций, 1.5–2 недели с тестами. Ломается: если появится второй процесс-писатель (запрещено D-3/ADR-0001 — один бинарь).

---

## 3. Альтернатива B — полный event sourcing (DSH-стиль)

Все домены — потоки событий; state — только проекции (`consumer_offsets`, перестраиваемые). Даёт: replay всего, fork сессий, «видимое = залогировано» в пределе. Берёт: Rust-код проекций на каждый домен, eventual consistency панели (лаг проекций), отладка «почему статус такой» через свёртку событий, миграции = переигрывание. Research-консенсус: избыточно для малой системы; наш реальный replay-кейс — только сессии и память (уже покрыты в A событиями и ревизиями). **Честный вывод: платим постоянной сложностью за общность, которая нужна двум доменам из восьми.**

## 4. Альтернатива C — классический CRUD + generic-аудит

State-таблицы, единый аудит-триггер (`audit_log(table, row_id, old, new, actor)`). Легче всех писать. Теряет: событие как первичный факт (аудит — побочный продукт, jsonb-диффы вместо осмысленных `kind`), идемпотентность и CAS «в лоб» на каждом месте, историю задач как продукт (панель «Сказано и сделано» строится по диффам). Донор уже показал, куда это ведёт (два пути записи). **Дешевле на старте, дороже с третьей недели.**

## 5. Альтернатива D — статус-кво донора (перенос 13 файлов AD как есть)

Отклоняется без проработки: 16 известных костылей, включая готовую потерю данных (path-PK+CASCADE) и слитые оси commands. Включена для честности матрицы.

---

## 6. Матрица

| Сила | A: гибрид | B: полный ES | C: CRUD+аудит | D: перенос AD |
|---|---|---|---|---|
| Читаемость состояния (в. 2) | **good** | poor (проекции) | good | good |
| История/replay/«видимое=залогировано» | good (потоки там, где нужны) | **good** | poor | fair |
| Инварианты (идемпотентность, CAS, оси) | **good** (конструкциями) | good | fair (руками) | poor |
| Стоимость Rust-кода | fair | poor | **good** | good |
| RLS/скоупы единым каркасом | **good** | fair | fair | poor |
| C-С1 (объём/деньги) | **good** (вехи+файлы) | fair (все события в БД) | good | fair |

## 7. Что сознательно НЕ рассматривали

Отдельные БД per-domain (F7); jsonb-everything/EAV (двойной анти-урок: yao-роботы, донор-projection — но projection как *снимок для чтения* остаётся); ORM-слои (sqlx с raw SQL — по ADR-0004); CQRS с шиной (один бинарь); хранение сырого stream-json в БД (C-С1 + C-Д1 решили файлами); внешние event-store (EventStoreDB и пр. — новый сервис против F7).

## 8. Что нужно узнать, чтобы решить

Ничего внешнего — вопросы владельца закрыты раундом 2. Рекомендация design: **A**. Открытые под-параметры для Decide: (а) политика доступа psql-владельца к state-таблицам (аудит-триггер на прямые UPDATE — да/нет); (б) retention session_events (предложение: 90 дней вехи, сырьё-файлы 30 дней, саммари вечно); (в) стартовый состав `command_kinds` (start|stop|answer|note|assign).
