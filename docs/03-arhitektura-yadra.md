# DeepSeek Harness — архитектура ядра (по исходникам)

Конспект по коду `reference/deepseek-harness` (v0.1.0-rc.8), 2026-08-20. Пути — относительно корня репозитория DSH.

> **Поправка к веб-обзорам (docs/01):** Standard/Code/Minimal/Creator — это **не профили, а agent presets** (другой слой). Профили — это `web` и `headless`.

Главные входные документы: `docs/architecture.md` (читать первым), `docs/cordis-primer.md`, `docs/cordis-tutorial/01..07`, `docs/cordis-api/*`, `AGENTS.md`.

---

## 1. Ядро Cordis

### Где лежит
Cordis **вендорится в исходниках**, не тянется из npm: `vendor/` — полный список и журнал локальных правок в `vendor/README.md` (18 пунктов расхождений с апстримом — обязательно к прочтению).

| Каталог | npm-имя (rescope в `@deepseek-ai`) | Роль |
|---|---|---|
| `vendor/cordis/src/` | `@deepseek-ai/cordis` 4.0.0-rc.7 | само ядро |
| `vendor/loader/src/` | `cordis-plugin-loader` | загрузка дерева плагинов из YAML |
| `vendor/include/src/index.ts` | `cordis-plugin-include` | вложенные конфиги + **патч-алгоритм** |
| `vendor/group/src/index.ts` | `cordis-plugin-group` | `cordis:group`, транзакционный апдейт поддерева |
| `vendor/hmr/src/index.ts` | `cordis-plugin-hmr` | горячая перезагрузка модулей и конфигов |
| `vendor/timer`, `vendor/logger-console`, `vendor/cosmokit`, `vendor/schemastery` | — | таймеры, логгер, утилиты, схемы конфигов |

Исходники ядра (~2600 строк): `context.ts` (146) — `Context`, прокси-доступ к сервисам; `fiber.ts` (754) — **самый важный файл**, жизненный цикл экземпляра плагина; `registry.ts` (337) — `ctx.plugin()`, `ctx.inject()`; `reflect.ts` (418) — `provide()`/трекинг сервисов; `events.ts` (352) — `emit/waterfall/parallel/serial`; `service.ts` (115) — базовый класс `Service`.

### Пять идей (из `docs/cordis-primer.md`)
1. **Плагин — объект, реализующий Service**: функция с полями `inject` и `apply(ctx)`, либо подкласс `Service`.
2. **Контекст — репозиторий сервисов**: сервис занимает стабильный ключ (`ctx.tools`, `ctx.llm`, `ctx.sessions`). Потребители ищут по ключу, а не импортом реализации.
3. **Зависимости через `inject`**: плагин ждёт появления названных сервисов; порядок загрузки выражен требованиями. `ctx.inject(deps, cb)` — сахар для `ctx.plugin({inject, apply: cb})`; коллбэк **выгружается и перезапускается** при смене любого требуемого сервиса.
4. **Типизированные события** через declaration merging TS.
5. **Регистрации — обратимые эффекты**: всё через `ctx.effect()` / `ctx.on()`, дизпоузеры собираются на fiber и раскручиваются в обратном порядке при выгрузке.

### Fiber
Fiber = один загруженный экземпляр плагина: состояние жизненного цикла, валидированный конфиг, эффекты. `ctx.effect(execute, label?)` (`fiber.ts:415`): execute выполняется сразу, дизпоузеры запускаются в **обратном** порядке при выгрузке; повторный вызов — no-op; `CordisError('INACTIVE_EFFECT')` на уничтоженном fiber. Состояния: `PENDING` → `LOADING` → активен → `UNLOADING`; создание эффекта во время `UNLOADING` отклоняется (правка №6).

### Сервисы
`Service(ctx, name)` вызывает `ctx.reflect.provide(name, this, this[Service.check])` — регистрация снимается при выгрузке владеющего fiber. Символы: `Service.init`, `Service.check` (предикат доступности), `Service.invoke` (вызываемый сервис, как `ctx.logger()`), `Service.extend`, `Service.tracker`, `Service.resolveConfig`.

### События — 4 режима диспетчеризации
Режим — часть публичного контракта (тег `@mode`, сверяется генератором каталога):

| Режим | Ждём? | Порядок | Возвращает? |
|---|---|---|---|
| `emit` | нет | регистрации | нет |
| `waterfall` | нет | регистрации | да |
| `parallel` | да | параллельно | нет |
| `serial` | да | регистрации | да |

**Waterfall — around-middleware**: слушатель получает `(...args, next)`; `next()` делегирует дальше, возврат без `next()` — короткое замыкание. `prepend: true` — только когда слушатель обязан идти раньше.

### Loader: строка конфига
`vendor/loader/src/config/entry.ts:9`:
```ts
interface EntryOptions {
  id: string            // стабильный id внутри дерева
  name: string          // module specifier
  config?: any
  group?: boolean|null  // строка — вложенная группа
  disabled?: boolean|null
  inject?: Inject|null
}
// + intercept?, isolate?: Dict<true|string>  (isolate.ts:5)
```
- **Интерполяция `!!js`** — только `config` (лениво, после активации инъекций, в контексте плагина) и `disabled` (при каждом решении о монтировании, в контексте loader). Остальное литерально (правки №15, №18).
- **Realm / `isolate`**: `isolate: { terminals: true }` — приватный экземпляр сервиса для строки/группы; `isolate: { fs: 'label' }` — именованный realm. Так preset даёт поддереву свой `ctx.fs`.
- **HMR**: `vendor/hmr` + `registerConfig()` (правка №9) — наблюдение за конфигом, коалесцирование, событие `hmr/config-update-failed`.

---

## 2. Профили и бандлы

### Профиль — композиция всего процесса
Реализация: `packages/boot/app-boot/src/profile.ts`. Профиль — каталог `$DSH_HOME/profiles/<name>/` (`$DSH_HOME` или `~/.dsh`):
- `package.json` — `dependencies` (внешние плагины, ставит pnpm) + `dsh.profile.bundles` (упорядоченный список бандлов);
- `cordis.patch.yml` — патч-слой пользователя;
- `pnpm-workspace.yaml` (`nodeLinker: hoisted`, `autoInstallPeers: false`).

```ts
PROFILE_TEMPLATES = {                                   // profile.ts:114
  web:      ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app'],
  headless: ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-headless'],
}
```
`web`/`headless` автоинициализируются; другое имя падает громко, пока не создано через `dsh plugin --profile <name>`.

### Бандл
npm-пакет с манифестом `"dsh": { "bundle": { "patch": "./cordis.patch.yml" } }`. Три шиппящихся:

| Пакет | Строк патча | Что даёт |
|---|---|---|
| `packages/bundle/base` → `dsh-base` | 451 | ядро: llm, session, tools, agent-loop, persistence, sandbox, approval, settings, credentials, skills, subagents, workflow… (~90 строк) |
| `packages/bundle/web-app` → `dsh-web-app` | 445 | webserver, apiproxy, storage, code-runtime, браузерный roster |
| `packages/bundle/headless` → `dsh-headless` | 35 | one-shot прогон, без сервера |

### Сборка дерева
`composeEntries(layers, warn)` (`profile.ts:413`) — один `applyEntryPatches([], layers.flat(), warn)` поверх пустого списка. Порядок слоёв (`apps/cli/src/profile-boot.ts:132-151`):
```
[] → патчи бандлов (в порядке dsh.profile.bundles)
   → <profile>/cordis.patch.yml
   → $DSH_HOME/cordis.patch.yml        ← машинно-локальный, старше per-profile
   → --patch оверлеи (порядок argv) + патч телеметрии
```
Семантика: id-адресный патч **заменяет весь `config`** строки (не мержит!); `insert` добавляет строки; ненайденная строка — предупреждение; пустой файл — ошибка (отключить слой = `[]`). Правка №11: insert-строки индексируются по мере добавления — поздний патч того же списка может настроить строку, вставленную ранним. User-слой живой: `watchUserPatches()` — транзакционная перекомпозиция, провал парсинга оставляет последнее хорошее дерево.

Инспекция:
```sh
dsh --profile web --dump-config          # с user-слоем и --patch
dsh --profile web --dump-default-config  # только бандлы
```

### Agent presets — Standard/Code/Minimal/Creator
Пакет `packages/preset/agent-presets` (README — самый плотный в репо); шиппящиеся — `apps/cli/config/agent-presets/`:

| Каталог | Имя | agent.cordis.yml |
|---|---|---|
| `standard/` | Standard | 252 стр.: fs, shell, поиск, skills, plan, goal, subagents, workflow |
| `code/` | PTC (Code Mode) | 263 стр.: то же, но инструменты через Code Mode SDK — модель пишет TS-программу |
| `minimal/` | Minimal | 88 стр.: persistent bash + str_replace_editor |
| `cordis/` | Creator | 263 стр.: standard + runtime-инспекция, скиллы авторинга пресетов |

Механика: пресет = каталог с `agent.cordis.yml` (top-level список строк) + опциональный `preset.yml` (display: name/description/order). Монтируется один раз на процесс под standing scope; сессия присоединяется парентингом scope key (`packages/core/scope`), резолв `agent → preset → global`. Сервис `ctx.agentPresets`: `list/resolve/mount/composeFrom/recompose/copy/remove/read/standingKeyFor`. Дефолт — настройка `agent-presets: { default: minimal }` в `settings.yaml`.

Правила: строка-сервис в пресете обязана сидеть в группе с `isolate` realm (иначе mount отклоняется); авторинг — только копированием каталога; смена пресета логируется событием `agent-preset/selected`; `cordis` и `code` — полные копии `standard`, патч-семантики на этом слое нет.

---

## 3. Главный агентный цикл

- Интерфейс: `packages/core/agent` — `ctx.agents`, `AgentRegistry`, `AgentFactory`, вокабуляр `agent/*`.
- Единственная реализация: `packages/core/agent-loop` (`index.ts` — плагин/сервис; `agent.ts` — `ReactLoopAgent`; `tool-calls.ts` — планирование параллельных/эксклюзивных вызовов).

Замена цикла: `AgentLoop` регистрирует себя как фабрику — `ctx.effect(() => ctx.agents.setFactory(this))` (`agent-loop/src/index.ts:350`); все создают агентов через `ctx.agents.create/resume`. Свой цикл = снять патчем строку `agent-loop` (`packages/bundle/base/cordis.patch.yml:436`) и вставить свою реализацию `AgentFactory`. `setFactory` — эффект: выгрузка возвращает реестр в прежнее состояние.

### Поток turn/step
**Step** = один запрос к модели + его инструменты. **Turn** = ноль и больше step'ов.
```
turn/start
  claim next-step input + сообщение из очереди
  сборка prompt sections + tool schemas
  → agent/pre-step (waterfall)     reject | enter(messages)
     step/start
     дописать вошедшие как user/message
     deriveMessages() из лога
     agent/request → llm/stream → assistant/chunk* → assistant/message
     tool/call* → tools/pre-execute → tools/execute → tools/post-execute → tool/result*
     step/end
     (инструменты просят ещё запрос или пришёл next-step ввод → следующий step)
  → agent/turn-stopping (serial)
turn/end
```
Waterfall'ы (обязаны звать `next()`): `agent/pre-step`, `agent/request`, `llm/stream`, `tools/pre-execute|execute|post-execute`.

События `agent/*` (`packages/core/agent/src/runtime-types.ts:159-290`): `created, disposed, status, inbox/{inserted,claimed,discarded,spliced}, session-start, pre-step, request, request-error, turn-stopping, error`.

Инбокс — один `send()`, три алиаса: `followup()` (FIFO next-turn, будит), `steer()` (next-step, будит), `inject()` (next-step, не будит).

Циклу НЕ принадлежат (это плагины): компакция (`agent/pre-step` + `agent/request-error`), ретраи (`packages/llm/llm-retry`), sandbox/permission/plan-mode (`tools/*`), сабагенты, персистентность, UI.

---

## 4. Сессии — append-only журнал

- Типы/стор: `packages/core/session/src/{types.ts,index.ts}` — классы `Session` (:425), `SessionStore` (:792); свёртка `surface.ts`; ремонт `repair.ts`. Док: `docs/subsystems/session.md`, `docs/persistence-catalog.md`.
- `Session` — append-only лог типизированных `SessionEvent`, единственный источник правды. История для LLM **выводится** (`deriveMessages()`, `index.ts:726`), не хранится. Replay = повторный вывод.
- Вокабуляр: `turn/start|end, step/start|end, user/message, assistant/chunk|message, tool/call|result, todo/write, request/header|context, session/end-seed`; расширяем declaration merging (компакция добавляет `compaction/*`, hooks — `hook/*`).
- **Инвариант «видимое модели = залогировано»**: всё, что попадает в запрос, реконструируемо из лога; проверяется runtime-инвариантом (`agent-loop/src/invariant.ts`). Новый вид видимого ввода = новый тип события. Seq непрерывный (`events[i].seq === i`), данные — lossless JSON (валидация прямо в `append`).

### Fork / resume
- `SessionStore.fork(source, boundary?, childSessionId?)` (`index.ts:1081`): `boundary` — включительный seq; ошибки `SESSION_ALREADY_EXISTS`, `INVALID_BOUNDARY`, **`OPEN_TURN`** (срез не может кончаться внутри открытого turn). Ребёнок: `meta: { cwd, parentSession, seedLength }`, маркер `session/end-seed`.
- `ctx.agents.resume({resumeSessionId, ...})` — через `ctx.sessionPersistence`; без бэкенда отклоняется с внятной ошибкой.

### Персистентность
- Шов `packages/session/session-persistence` (`ctx.sessionPersistence`: `locate/readRaw/create/append/prepare/load/inspect/readFrom/list/listSnapshots`).
- Бэкенды: `-jsonl` (по умолчанию, `.jsonl.zstd`), `-sqlite`. Общий `PersistenceCoordinator`: батчинг, ленивая материализация, ремонт хвоста после краха, quiescent disposal.
- **Ремонт, не усечение**: незакрытый turn сохраняется, дописываются синтетические закрыватели (error `tool/result` на каждый неотвеченный вызов, затем `step/end?` + `turn/end {interrupted}`).
- Раскладка: `<root>/--<normalized-cwd>--/<encoded-id>/session.jsonl.zstd`; первая строка — неизменяемый `SessionHeader` (включая `agentPreset` — он решает, что увидит возобновлённая сессия).

### Поиск/трассировка
`packages/session-query/session-query` (`ctx.sessionQuery`): `listSessions, readSession, filterSessions, filterEvents, listEvents (current/shadowed/log-only), readSurface, readEvent, traceSession` (дерево ветвей), `traceEvent`. Поиск — `session-query-sqlite` (FTS5). Модельная обёртка: `tool-session-query`.

---

## 5. Конфигурация — три файла, три владельца

Гейт: `scripts/verify-config-source-ownership.ts`.

1. **`cordis.patch.yml`** — композиция (инженерный слой): какие плагины смонтированы, entry-config.
2. **`settings.yaml`** (`$DSH_HOME/settings.yaml`) — пользовательские значения. Шов `packages/settings/settings` (`ctx.settings`), провайдер `settings-file` (watch, debounce 100ms, атомарная запись, writer-lock, сохранение YAML-комментариев). Разрешение: схема-дефолты → entry-config → секция пользователя. API: `register(ns, schema, ...)`, `get/watch/update/replace/mutate`, события `settings/updated`. Namespace'ы: `agent-default-model, agent-loop, agent-presets, permission, llm-deepseek, llm-pi-ai, shell, web-search-deepseek, locale, ui-*`.
3. **`.credentials.yaml` + `.env`** — секреты. Шов `packages/credentials/credentials`, провайдер `credentials-local`, 4 слоя по приоритету: env процесса > `$DSH_HOME/.credentials.yaml` (единственный записываемый) > `<cwd>/.env` > `$DSH_HOME/.env`. **`settings.yaml` никогда не хранит ключей** — только credential reference (`<ROUTE>_API_KEY`).

### Провайдеры моделей
Два адаптера шва `ctx.llm` (`packages/llm/llm`):
- `llm-deepseek` — нативный (fetch + SSE), маршрут `deepseek-official`; конфиг: `apiKeyEnv` (`DEEPSEEK_API_KEY`), `baseURL`, `thinking`, `reasoningEffort (off|low|high|max)`, `maxTokens`, `retryPolicy`, `models[]`.
- `llm-pi-ai` — каталог провайдеров (Anthropic, OpenAI, Bedrock, Vertex, Azure…) + произвольные шлюзы; маршрут `deepseek`.

Пример (`docs/user/guide/providers.md`):
```yaml
llm-pi-ai:
  providers:
    my-gateway:
      apiKeyEnv: GATEWAY_API_KEY
      api: openai-completions
      baseURL: https://gateway.example/v1
      models:
        - id: vision-preview
          input: [text, image]
```
Дефолтная модель новых сессий: `packages/core/agent-default-model` — `provider: deepseek-official`, `model: deepseek-v4-flash`. Полный справочник полей: `docs/config-catalog.md`.

### CLI
`apps/cli/src/{args.ts,bin.ts}`:
```
dsh --profile <name> [--patch f.yml]... [app args...]
dsh --profile headless "задача"
dsh web                                # алиас --profile web
dsh plugin --profile <name> <pnpm args>
dsh --profile <name> --dump-config | --dump-default-config
```
Лаунчер парсит только свои флаги; первый нераспознанный токен начинает аргументы приложения (`ctx.cmdlineArgs`).

---

## 6. Структура монорепы

`pnpm-workspace.yaml`: `vendor/*`, `packages/*/*` (двухуровневая группировка), `native/landlock-run`, `apps/*`, `website`. Корень `@deepseek-ai/dsh-root@0.1.0-rc.8`, Node ^22.19||>=24, pnpm 11.7.

**apps/**: `cli` (`@deepseek-ai/dsh` — лаунчер профилей, `dsh plugin`, шиппящиеся agent-presets), `web` (Vite-фронтенд SPA).

**packages/** по группам (ключевое):
- **boot**: `app-boot` (boot-клей, профили, патчи), `cmdline`
- **bundle**: `base`, `web-app`, `headless`
- **core**: `agent` (интерфейс), `agent-loop` (реализация), `agent-default-model`, `agent-tool-presentation` (Code Mode / native / both), `scope`, `session`, `system-prompt`, `tools` (реестр + пайплайн исполнения, 88 KB)
- **llm**: `llm`, `llm-deepseek`, `llm-pi-ai`, `llm-retry`, `token-meter`
- **session** (14 пакетов): persistence (+jsonl/sqlite), checkpoint-policy, projection(+cache), stats, telemetry(+otel), title(+3 провайдера)
- **session-query**: `session-query`, `-sqlite`, `tool-session-query`, `session-log-export`
- **settings/credentials/storage**: швы + провайдеры (storage: json/sqlite/domain)
- **fs/shell/subprocess/terminal/sandbox/e2b**: шов + local/sandbox-реализации + tool-обёртки; `e2b` — удалённая песочница (один swap переносит Bash/PTY/LSP)
- **subagent** (11): шов `ctx.subagents`; драйверы spawn/fork-in-process, `-acp`, `-dsh-sdk`, **`-claude-code`**, **`-codex`**; tool-обёртки
- **workflow/jobs/schedule**: durable-оркестрация (`tool-ralph`!)
- **host/api/client** (40 клиентских пакетов): webserver, apiproxy, gateway (Typert Remote), браузерная половина — каждый клиентский пакет объявляет `dsh.client: { inject, platform: 'web', immediately? }` — браузерный roster, сканируемый в `window.__DSH_BOOT__`
- **sdk/acp**: JSON-RPC stdio SDK; Agent Client Protocol для редакторов
- **context/compaction/spill/guard/interaction/plan/goal/todo/skill/web/lsp/mcp/hooks/attachment/code-runtime**: agent-instructions (AGENTS.md/CLAUDE.md!), @file-ссылки, компакция, вынос гигантских результатов, слэш-команды, permission-presets, plan-mode, skills, web-поиск (deepseek/exa/perplexity), LSP, MCP-клиент, мосты hook-конфигов **Claude Code и Codex**
- **typert**: генерация Remote-метаданных и Zod-схем из TS
- **extensions**: `tool-cordis` — **саморефлексия**: модель инспектирует живой рантайм и монтирует написанные ею плагины
- **experimental**: `agent-team` (ростер, доска задач, почта)
- **preset**: `agent-presets`, `persona`
- **runtime-diagnostics**: реестр runtime-инвариантов
- **test-support**: `llm-mock-server`, `llm-replay`, `agent-loop-testkit`…

Прочее: `native/landlock-run` (нативная песочница Linux), `python/`, `website/` (VitePress), `scripts/` (~60 генераторов/верификаторов, всё "Generated by" в docs/ проверяется в CI), `.agents/notes/implemented/` — датированные Agent Notes с решениями («почему так» — лучший источник).

---

## Порядок чтения для погружения

1. `docs/architecture.md`
2. `docs/cordis-primer.md` → `docs/cordis-tutorial/01..07`
3. `vendor/README.md` (18 локальных правок Cordis)
4. `packages/boot/app-boot/README.md` §Profiles + `src/profile.ts`
5. `packages/preset/agent-presets/README.md`
6. `packages/core/agent-loop/README.md`
7. `docs/subsystems/{core,session,tools,persistence,settings}.md`
8. `docs/event-producer-consumer.md`, `docs/capability-seams.md`

## Три места, где легко ошибиться

- Профиль (`web`/`headless`, `$DSH_HOME/profiles/`) ≠ agent preset (`standard`/`code`/`minimal`/`cordis`). Первый композирует процесс, второй — одного агента.
- Патч **заменяет весь `config`** строки, не мержит: переопределяя одно поле, переписываешь все.
- `settings.yaml` никогда не содержит значений ключей — только ссылки на credential store.
