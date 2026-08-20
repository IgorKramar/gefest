# yao (Yao Agents) изнутри — карта заимствований для Гефеста

Разбор исходников `reference/yao` (коммит `94ab88a`, 2026-08-20). Цель — архитектурные решения для собственного оркестратора (ADR-0001, фаза Ф0.5): берём идеи, не код. По каждому разделу — вердикт «брать / не брать».

---

## 1. Раннер Claude Code (`agent/sandbox/v2/claude/`)

### Запуск процесса
Не exec напрямую, а heredoc-скрипт в `bash -c` внутри контейнера (`platform.go:81-107`): системный промпт **пишется в файл** (нет лимита argv и экранирования), в stdin уходит **только последнее user-сообщение** — историю держит сам Claude Code в session-файлах. `set -e` вокруг записи промпта — чтобы не стартовать CLI молча без промпта.

### Флаги CLI (`command.go:307-360`)
Всегда: `--input-format stream-json --output-format stream-json --include-partial-messages --verbose`. Условно: `--session-id <uuid>` (первый ход) / `--resume <uuid>` (продолжение) / `--continue` (нет chatID); `--name yao-<chatID>` — метка процесса в ps для точного `pkill`; `--append-system-prompt-file` на continuation-ходах; `--mcp-config` + `--allowedTools`; из DSL пробрасывается белый список из трёх опций (`max_turns`, `disallowed_tools`, `allowed_tools`).

### Resume: детерминированный UUID (`command.go:26-57`)
```go
var yaoSessionNS = uuid.MustParse("f47ac10b-...")
uuid.NewSHA1(yaoSessionNS, []byte(assistantID+":"+chatID))  // UUIDv5
```
- ID сессии Claude = **чистая функция** от (agent, chat) — не хранится в БД.
- Флаг «это продолжение» — отдельно, в KV-сторе с TTL 90 дней, ключ включает workspaceID (session-файлы живут внутри workspace).
- Метка ставится **сразу после старта процесса**, до чтения стрима: CC создаёт файл сессии при старте, даже упавший стрим означает «дальше только `--resume`».
- Фолбэк без chatID: `ls $CLAUDE_CONFIG_DIR/projects` в песочнице.

### Парсер stream-json (`parse.go`, 807 строк, явная стейт-машина)
Обрабатывает: `system` (→метаданные), `stream_event` (`content_block_start/delta/stop`), `assistant` (usage; tool_use; текст только при `stop_reason != ""`), `user` (`tool_result` → закрытие execute-сообщения), `result` (конец, стоимость/токены), `error`.

**Игнорирует молча** (важно при повторении): `message_start/delta/stop`; все блоки кроме `tool_use` в `content_block_start`; **`thinking_delta` и `signature_delta`** (reasoning в UI не течёт); невалидный JSON — `continue`, поток не рвётся; строки > 50 МБ дренируются (защита от гигантского `result`).

Модель сообщений: `message_id` **переиспользуется** между фазами тула (running при `content_block_start` → completed при `tool_result`) — фронт мёржит в одну карточку. `parent_tool_use_id` вытаскивается из каждой строки → дерево саб-агентов. Семантические типы: `Agent→agent`, `TodoWrite→todo`, `Enter/ExitPlanMode→plan`, `AskUserQuestion→question`. Короткое резюме тула: для Bash — команда, для Read/Write/Edit — file_path, обрезка 80 символов.

### Ошибки и обрывы (`session.go`)
- **stderr никогда не отменяет стрим** — копится и логируется.
- После `result` процесс **убивается SIGKILL** — воркараунд известного зависания stream-json-режима CLI после result; SIGKILL, а не SIGTERM, чтобы CC не успел убить своих детей (веб-серверы в песочнице выживают).
- Exit 0 без `result` при непустом stderr = «claude CLI setup failed» (типовой случай: упал на конфиге и вернул 0 — та же ловушка, что наш S1b).
- `Cleanup`: при нормальном завершении **ничего не убивает** (дети живут); иначе `pkill -9 -f yao-<chatID>`.
- Heartbeat парсера: раз в 30 с trace `lines/elapsed/lastEvent` — диагностика «повис на input_json_delta».

### memory.go — генератор auto-memory
Пишет в CC auto-memory директорию три файла: `environment-context.md` (workspace, workdir, каталог инструментов; в description — триггеры под механику recall), `extension-skills.md`, `MEMORY.md` — **только если файла нет** («CC сам ведёт этот файл — перезапись уничтожила бы его записи»).

### ENV (`command.go:135-305`)
`HOME = WORKDIR`; **`CLAUDE_CONFIG_DIR = $WORKDIR/.yao/assistants/<aid>`** — изоляция сессий per-agent; git-идентичность workspace: `GIT_CONFIG_GLOBAL`, `GIT_SSH_COMMAND -F <ws>/ssh/config`, `XDG_CONFIG_HOME`. Хак совместимости: `CLAUDE_CODE_EXTRA_BODY = {"metadata":{"user_id":"<sha256[:8]>"}}` — CLI шлёт объект в user_id, который сторонние Anthropic-совместимые API отвергают.

> **Брать:** heredoc + промпт в файле; UUIDv5 сессии + TTL-флаг continuation; переиспользование `message_id` running→completed; `parent_tool_use_id` в каждой строке; stderr как информация, не сигнал отмены; лимит длины JSONL-строки; SIGKILL после `result`; Cleanup, не трогающий детей; `CLAUDE_CONFIG_DIR` per-agent; правило «не перезаписывать MEMORY.md».
> **Не брать:** suspend/resume групп и «усыновление» Agent-тулзов (лечение ограничения их приёмника — у нас `dict[tool_id → group]`); игнорирование `thinking_delta` (у нас это регресс UX); белый список из трёх флагов — слишком узко.

---

## 2. Жизненный цикл песочниц (`agent/sandbox/v2/`, `/sandbox/v2/`)

### Четыре политики (`types.go:68-82`)
`OneShot | Session | LongRunning | Persistent`; дефолты: stop 2 с, session idle 30 мин, longrunning idle 2 ч, oneshot max-age 8 ч. Идентификатор контейнера — **чистая функция от политики**: session → `{owner}-{assistant}-{chat}`, longrunning → `{owner}-{assistant}.{workspace}`.

### Создание/возобновление (`lifecycle.go:180-231`)
`Get → IsStopped? → StartBox → BindWorkplace` (переезд контейнера между workspace без пересоздания — сброс кэша FS). `StartBox` ждёт entrypoint экспоненциальным пробником (20 мс → 2 с) на совпадение UID — лечит гонку «exec --user раньше usermod».

### Watcher вместо поллинга из запроса (`watcher.go`, интервал 30 с)
Смена статуса → Alert; `LongRunning` istёк maxLifetime → Remove; `OneShot` старше 8 ч → Remove (страховка от потерянного cleanup); idle > timeout: `Session → Remove`, `LongRunning → Stop`. **Два таймстампа**: `lastCall` (бизнес-активность, по нему idle) vs `lastHeartbeat` (не сбрасывает idle) — «жив» ≠ «работает».

### Восстановление после рестарта
Реестр восстанавливается **из docker-лейблов** (`managed-by=yao-sandbox`, `sandbox-id/-owner/-policy`, `workspace-id`) — БД не нужна.

### Prepare (`prepare.go`)
Шаги file/copy/exec; идемпотентность через маркер `.yao/prepare/<aid>/done`, содержимое = **хэш конфига** — изменился конфиг, `once`-шаги проигрываются заново; `ignore_error` на шаг.

> **Брать:** политики с явными таймаутами; идентификатор как функция политики; `lastCall` vs `lastHeartbeat`; фоновый watcher; `LongRunning→Stop`, `Session→Remove`; OneShot max-age; маркер prepare с хэшом конфига; `waitEntrypoint`; каталог образов как YAML-данные.
> **Не брать:** трёхуровневый выбор нод (у нас один хост); `host`-режим исполнения на голой машине (дыра); VNC/desktop — нет GUI-задач.

---

## 3. Модель задач и статусов — ДВЕ несвязанные системы (главный вывод)

### Канбан (`agent_task`, 1:1 с `agent_chat` по `chat_id`)
`column_id, position, pinned, priority, tags; run_status: pending|queued|running|waiting|completed|failed|cancelled; queue_priority, queued_at; progress, current_step, error_message, run_count; schedule, instruction, summary, outputs, metadata (json); archive_status`. **Стадии — не enum, а строки таблицы `agent_board_column`**; доски — из YAML-шаблонов с i18n. Полный REST API досок и задач есть (`openapi/agent/board`, `openapi/agent/task`): CRUD, move, run/stop, ws/stream, columns/reorder.

### Robot / Mission Control (`agent_execution`)
Фазы в коде: `inspiration|goals|tasks|run|delivery|learning` (+ сквозная роль `host`). **«Validation» как стадии в коде нет** — только поле `TaskResult.Validation`, заполняемое Delivery-агентом. Статусы: `pending|running|paused|completed|failed|cancelled|confirming|waiting` (`confirming` — ждём подтверждения плана человеком, `waiting` — пауза посреди исполнения). Хранение: **по JSON-колонке на выход каждой фазы** + `ResumeContext{TaskIndex, PreviousResults}`. Машина переходов не декларативная — размазана по коду.

> **Брать:** «колонка (человек) ≠ run_status (машина)» — задача может лежать в Review, будучи completed; шаблоны досок YAML; queue_priority в задаче; JSON-колонка на фазу (дёшево дебажить и ретраить с фазы); `confirming`/`waiting` как first-class статусы human-in-the-loop; `ResumeContext`; `outputs` json на задаче.
> **Не брать:** две параллельные системы задач (канбан + executions почти не связаны — удвоение сущностей); шесть фаз P0–P5 (планирует сам Claude Code); недокументированную машину переходов — если берём статусы, пишем таблицу переходов одним словарём.

---

## 4. Доставка команд и очереди

Путь: `POST /tasks/:chat_id/run` → `daemonRegistry.LoadOrStore(chatID)` (**дедупликация двойного запуска**) → `GlobalQuota.TryAcquire(teamID)` (лимит 9, иначе `queued` + heap по приоритету) → runDaemon → claude.Runner.Stream → gRPC в контейнер.

**Подтверждения доставки нет.** Компенсация — пересборка состояния: монотонный `Metadata.Sequence`, ring buffer в демоне (сообщения >1 МБ не кладутся), `Watch` реплеит с `AfterSeq`, маркер `read_complete{has_more,last_seq,live}`, потом live; демон умер → `watchFromDB` с курсором. Клиент дедуплицирует по `message_id`.

При падении сервера yao: контейнеры выживают (лейблы); **сообщения теряются** — `FlushBuffer` пишет в БД одним батчем в defer в конце стрима (крах в середине = ноль сохранённых); задачи чинит reaper (каждые 5 мин: `running/queued` без живого демона и `updated_at` старше 10 мин → `failed`); у роботов recovery различает `running→failed`, но **`waiting/confirming` сохраняются** (ждут человека, не процесс). Прерывание — поллинг `Interrupt.Peek()` каждые 500 мс.

> **Брать:** `LoadOrStore` против двойного запуска; sequence + ring buffer + `read_complete` как замена ack (в Postgres/SSE ложится 1:1); курсорный replay из БД; health-reaper «running без живого исполнителя → failed»; разное recovery для running (→failed) и waiting (→сохранить, уведомить); graceful/force контексты; per-team квота, идемпотентный `TryAcquireSlot`.
> **Не брать:** батчевую запись сообщений в конце стрима (**прямая потеря при краше** — писать инкрементально); дроп сообщений в полный канал без учёта в last_seq; тикерный поллинг (в Python — `asyncio.Queue`/`Event`); SSE-в-фейковый-ResponseWriter (техдолг ради import cycle); in-memory очередь без персистентности.

---

## 5. A2O-прокси (Claude Code поверх чужой модели)

Реализация прокси — вне репо (бинарь `tai`). yao делает две вещи: (1) `ANTHROPIC_BASE_URL = http://127.0.0.1:3099/c/<connectorID>`, `ANTHROPIC_API_KEY = "dummy"`, а **имя модели становится ключом маршрута** (`ANTHROPIC_MODEL = "default"|"heavy"|"light"`, настоящее имя — в `*_NAME` для показа человеку); (2) push конфига маршрутов в прокси между ходами (backend/model/apiKey/routes). Для настоящего Anthropic-коннектора прокси не используется. Ограничение CLI: разные хосты для разных тиров в одном процессе CC невозможны.

> **Брать:** «имя модели = ключ маршрута»; локальный прокси на 127.0.0.1 — настоящие ключи не живут в env агента (`dummy`); конфиг отдельно от запуска (обновляем между ходами).
> **Не брать:** доставку JSON через `echo '<escaped>' | cmd` (мина экранирования — слать POST); best-effort проглатывание ошибок конфига; три тира — добавить, когда появится потребность.

---

## 6. Схема данных

Паттерн: у каждой сущности автоинкрементный PK **и** бизнес-ключ строкой (`chat_id/board_id/execution_id`), наружу — только бизнес-ключ. `chat_id` = идентификатор и задачи, и диалога (1:1). На чате — `last_workspace/last_connector/last_mode` («продолжить там же»).

**Осознанно нет в БД:** workspaces (метаданные `.workspace.json` в самом томе; `DefaultWorkspaceID = sha256(owner:node)[:6]` — материализуется лениво); песочницы (sync.Map + docker-лейблы); сессии CC (UUID вычисляется, флаг в KV); файловых миграций нет (DSL-модели).

> **Брать:** PK + бизнес-ключ; `chat_id` как единый id задачи-диалога; json-колонки для outputs/metadata/фаз; `sequence` на сообщении; `last_*` на чате; детерминированный DefaultWorkspaceID; метаданные workspace рядом с данными.
> **Не брать:** роботов как 20+ колонок в таблице `member` (EAV-по-бедности); отсутствие таблицы песочниц (Postgres уже есть — таблица дешевле парсинга лейблов); отсутствие версионируемых миграций.

---

## Итог: топ-5 для Гефеста

1. **UUIDv5 сессии CC от (agent, chat) + TTL-флаг continuation** — минус таблица, минус класс гонок.
2. **Sequence + ring buffer + `read_complete{last_seq, live}`** вместо ack — но писать сообщения в Postgres **инкрементально**, не батчем в defer (анти-урок yao).
3. **`lastCall` vs `lastHeartbeat` + фоновый watcher** (Session→удалить, LongRunning→остановить, OneShot→max-age).
4. **Prepare-шаги с маркером, содержащим хэш конфига** — идемпотентная инициализация окружения исполнителя.
5. **«Имя модели = ключ маршрута» + локальный прокси** — ключи провайдеров не живут в env агента.

Два «не повторять»: батчевая запись сообщений в конце стрима; две параллельные модели задач без связи.
