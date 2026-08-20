# Система плагинов DSH — конспект автора плагина (по исходникам)

Конспект по коду `reference/deepseek-harness`, 2026-08-20. Пути — от корня репозитория DSH.

Иерархия понятий: **Plugin** (модуль с `apply`) → **Bundle** (npm-пакет с `dsh.bundle.patch`, слой конфигурации) → **Profile** (каталог `$DSH_HOME/profiles/<name>` с `dsh.profile.bundles`). Ничто не является одновременно бандлом и профилем.

---

## 1. Анатомия плагина

### Точка входа — три формы (`docs/user/develop/basic/index.md`)

```ts
// функциональная (основная)
import type { Context } from '@deepseek-ai/cordis'
export const name = 'hello-plugin'
export const inject = ['tools']                 // требуемые сервисы
export const Config: Schema<Config> = Schema.object({ ... })
export function apply(ctx: Context, config: Config) { /* регистрации */ }

// объектная
export default { name, inject, apply(ctx) {} }

// классовая — когда плагин САМ предоставляет сервис
export default class MyService extends Service {
  static inject = ['tools']
  constructor(ctx: Context) { super(ctx, 'myService') }  // → ctx.myService
}
```

`Config` обязан быть Schemastery-схемой, не голым объектом — иначе не будет валидации и дефолтов.

### Lifecycle (Fiber)
```
PENDING → LOADING → ACTIVE (→ FAILED)
ACTIVE → UNLOADING → DISPOSED
```
Явных `onLoad/onUnload` нет — вместо них эффекты:
- `apply(ctx, config)` выполняется, только когда все `inject`-сервисы готовы;
- `ctx.effect(() => { ...; return () => cleanup() })` — ресурс с диспоузером;
- всё зарегистрированное через `ctx` (`ctx.on`, `ctx.tools.register`, `ctx.slots.register`…) снимается автоматически при выгрузке;
- исчезновение required-сервиса → плагин диспоузится и переподнимается, когда сервис вернётся;
- диспоузеры — в обратном порядке (асинхронные конкурентно; строгий порядок — внутрь одного `ctx.effect`);
- HMR работает «бесплатно» именно потому, что все регистрации — эффекты.

### Манифест: три ветки `dsh.*`
Типы: `packages/boot/app-boot/src/profile.ts:41-70`, `packages/client/modules/src/index.ts:49-63`.

**A. `dsh.bundle`** — что даёт пакет:
```json
{ "name": "dsh-hello-plugin", "type": "module", "main": "index.js",
  "files": ["index.js", "cordis.patch.yml"],
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } } }
```
Пакет без `dsh.bundle` ставится, но слой не активируется (предупреждение, `apps/cli/src/plugin.ts:60-80`).

**B. `dsh.profile`** — каталог профиля; пишется CLI, руками не редактируют:
```json
{ "dsh": { "profile": { "bundles": ["@deepseek-ai/dsh-base", "dsh-hello-plugin"] } } }
```

**C. `dsh.client`** — браузерная половина (Web UI):
```json
{ "exports": { ".": {...}, "./client": {...} },
  "dsh": { "client": {
    "platform": "web",         // обязательное; != 'web' игнорируется
    "inject": ["@deepseek-ai/dsh-client-ui-conversation"],
    "immediately": true,       // stage-1 prefetch; иначе лениво
    "external": ["<pkg>/client"]
  } } }
```
`dsh.client` без `exports["./client"]` — жёсткая ошибка.

### Patch-файл бандла (`cordis.patch.yml`)
Тип `PatchOptions` — `vendor/include/src/index.ts:145-156`:
```yaml
- insert:                       # вставка новых строк
    - id: hello
      name: dsh-hello-plugin    # имя пакета, не путь
      config: { greeting: 'Hi' }
- id: webserver                 # переопределение по id
  config: { host: 127.0.0.1, port: 3081 }
- id: some-row                  # отключение
  disabled: true
```
- **Патч заменяет весь `config`, не мержит ключи.**
- `insert` с `id:` — внутрь группы; без — в корень.
- `!!js`-скаляры — ленивые выражения в контексте строки: `port: !!js ctx.webStartup.port ?? 8080`.

### Порядок слоёв (что бьёт что)
1. Патчи бандлов в порядке `dsh.profile.bundles` (`dsh-base` первым)
2. `$DSH_HOME/profiles/<name>/cordis.patch.yml`
3. `$DSH_HOME/cordis.patch.yml` (машинные — бьют профильный)
4. `--patch <path>` в порядке argv

---

## 2. Эталонные примеры в репо

- **Минимальный бандл целиком**: `apps/cli/tests/built-bin.e2e.ts:57-130` — package.json + cordis.patch.yml + plugin.mjs.
- **Опциональный провайдер**: `packages/subagent/subagent-codex/` — патч из 4 строк (`insert: [{id, name}]`), плагин с `inject = ['subagents', 'subprocess']`, zod-Config, `ctx.subagents.registerProvider(...)`. Все dsh-пакеты — **peerDependencies** (контракт «один cordis на процесс»).
- **Двухголовый UI-плагин**: `packages/client/ui-plan/` — Host-половина с **пустым `apply()`** (нужна, чтобы строка появилась в дереве и клиентский сканер её увидел), браузерная половина в `src/client/index.ts` со слотами и локалью.
- **Оверлеи-примеры**: `examples/web-schedule/cordis.yml`, `examples/mcp-memory/*.cordis.yml` (один MCP-сервер = одна строка `dsh-mcp-client`), `examples/web-cordis/cordis.yml`; полные деревья — `examples/jsonrpc-agent/minimal.cordis.yml`, `examples/headless-agent/cordis.yml`.

---

## 3. Карта «возможность → точка регистрации»

Канон: `docs/cookbook/extension-cookbook.md`.

| Возможность | Регистрация |
|---|---|
| Tool | `ctx.tools.register(defineTool({...}))`, `inject=['tools']` |
| Ограничение тулов | `ctx.tools.restrict({allow,deny})` (скоуп-локально) |
| Монотонный запрет | `ctx.tools.guard(exec => reason\|undefined)` |
| Презентация (Code Mode) | `ctx.tools.presentAs(mode)` |
| LLM-адаптер | `ctx.llm.registerAdapter(['my-provider'], new MyAdapter())` |
| Skills | `ctx.skills.registerProvider(create)` / `ctx.skills.register(skill)` |
| System prompt | `ctx.systemPrompt.section({name, order, text})` |
| Storage | `ctx.storage.mount(form, facility)`, `ctx.storageDomain.open(spec)` |
| Sandbox | реализовать `SandboxProvider.confine(argv, policy)` |
| Subagent-провайдер | `ctx.subagents.registerProvider(provider)` |
| Команды | `ctx.commands` |
| UI-слот (браузер) | `ctx.slots.inject(key, () => ctx.slots.register({...}, Component))` |
| Узел чата | `ctx.conversationEvents.register(def)` + слот `conversation.chat.node` |
| Карточка настроек | Host: `installSettingsSection(...)`; браузер: слот `settings.plugin.item` с `key: ns` |
| Динамические плагины | `ctx.dynamicCordisRunner.define/run/stop/undefine` |
| Свой сервис | `class X extends Service` + declaration merging `interface Context { x: X }` |

### Перехват через события (без модификации ядра)
Waterfall (вернуть решение или `next()`): `tools/pre-execute` → `PreToolDecision` (allow/deny/ask), `tools/execute` (таймаут/ретрай/метрики), `tools/post-execute`, `llm/stream`, `system-prompt/assemble`, `agent/pre-step`, `agent/request`, `agent/request-error`.

```ts
export const name = 'permission-gate'
export function apply(ctx: Context) {
  ctx.on('tools/pre-execute', async (exec, next): Promise<PreToolDecision> => {
    if (!(await isAllowed(exec))) return { kind: 'deny', reason: 'Denied by policy.' }
    return next()
  })
}
```

Изоляция сервисов в конфиге: группа с `isolate: { shell: true }` получает приватный инстанс сервиса.

---

## 4. CLI: `dsh plugin ...`

Реализация: `apps/cli/src/{args.ts:158-172, plugin.ts, bin.ts}`. **Это тонкий форвардер в pnpm** — работает любой глагол pnpm:

```sh
dsh plugin --profile demo add ./hello-plugin              # локальный чекаут
dsh plugin --profile demo add ./hello-plugin-0.1.0.tgz    # pnpm pack
dsh plugin --profile demo add dsh-hello-plugin            # npm
dsh plugin --profile tui  add github:you/plugin#<sha>     # пин коммита — рекомендуется
dsh plugin --profile demo add file:../plugin              # / link:../plugin
dsh plugin --profile demo remove/list/update/why/install ...
```

Раннер (`runPlugin`): init профиля при отсутствии → якорение относительных путей от **вызывающего** каталога → `spawnSync('pnpm', ...)` → `reconcilePlugins()`: сверка по установленному состоянию — каждая зависимость с `dsh.bundle.patch` попадает в `dsh.profile.bundles`, исчезнувшая — удаляется (значит `update`, добавивший `dsh.bundle`, активирует бандл сам).

**Ловушка GitHub-установки**: git-инсталл тянет исходники; нужен самодостаточный `prepare`, а пользователь должен явно разрешить сборку:
```yaml
# $DSH_HOME/profiles/<name>/pnpm-workspace.yaml
allowBuilds: { dsh-hello-plugin: true }
```
Это разрешение исполнить чужой код вне песочницы агента. Безопаснее: npm с собранным `lib/` или tgz.

Смена набора бандлов требует перезапуска; правки `cordis.patch.yml` подхватываются горячо.

---

## 5. Python SDK (`python/`)

- `python/sdk/` — `deepseek-harness-sdk` (модуль `deepseek_harness`); `python/sdk-runtime/` — wheels с бинарём `dsh-jsonrpc-agent` (Node на машине не нужен).
- Говорит с рантаймом по JSON-RPC поверх stdio, держит подпроцесс, ведёт сессии.

```python
from deepseek_harness import DeepSeekHarness
with DeepSeekHarness(provider="deepseek-official", model="deepseek-v4-flash",
                     cordis="examples/jsonrpc-agent/minimal.cordis.yml") as h:
    result = h.run("Fix the failing tests.", session_id="example-001")
```

SDK плагины не пишет — он **выбирает композицию** (`cordis=<path>` / `DSH_CORDIS_CONFIG`); единственное требование — сохранить строку `@deepseek-ai/dsh-sdk-jsonrpc-server`. Расширение — по-прежнему TS/YAML.

---

## 6. Расширение Web UI

Механика — `packages/client/modules` (`docs/subsystems/client-modules.md`):
1. Host-сервис `ctx.clientModules` сканирует дерево на пакеты с `dsh.client` (platform web).
2. Граф `WebBootGraph` инжектится в `<head>` как `window.__DSH_BOOT__`.
3. Бандлы отдаются `GET /plugins/<pkg>/client.js?rev=<hash>`; `immediately: true` — префетч, иначе лениво.
4. **Пересборка веб-приложения не нужна** — клиентский плагин появляется, как только смонтирована Host-строка.

Единственная точка расширения — **слоты** (`packages/client/runtime/src/client/slots.ts`):
```ts
ctx.slots.inject(slotKey, () => ctx.slots.register({
  name: slotKey, key?, locale?, order?,
  inject: (...) => ({ ...фасад для компонента })
}, ReactComponent))
```
Известные слоты: `root` (регистрироваться нельзя — single), `shell.overlay`, `conversation.input.plan`, `conversation.chat.node`, `settings.plugins.tab`, `settings.plugin.item`. `SlotMap` расширяется declaration merging.

Ограничения сборки клиентской половины: lazy-CJS factory (внутри репо — пресет `packages/client/tsdown.client.ts`, наружу не публикуется — формат воспроизводить самому); **запрещены value-импорты между клиентскими плагинами** (только `import type`), взаимодействие через сервисы; dsh-зависимости — peerDependencies.

---

## Чек-лист своего плагина

1. Пакет: `type: module`, `exports["."]` (+ `"./client"` для UI), dsh-зависимости в `peerDependencies`.
2. `src/index.ts`: `name`, `inject`, `Config` (Schemastery), `apply(ctx, config)`; настраиваемое — в конфиг, не в хардкод.
3. Регистрации только через `ctx.*` / `ctx.effect` — иначе сломаются HMR и выгрузка.
4. `cordis.patch.yml` с `- insert: [{id, name}]` + `"dsh": {"bundle": {"patch": "./cordis.patch.yml"}}`.
5. Отладка без установки: `pnpm dsh web --patch ./my-plugin/cordis.yml` (путь к модулю в патче — абсолютный).
6. Установка: `dsh plugin --profile <name> add ./my-plugin`; проверка `--dump-config` (появится `# == my-plugin`).
7. Распространение: npm с собранным `lib/` или tgz; GitHub — только с `prepare` и предупреждением про `allowBuilds`. Тег для дискаверабилити — `dsh-plugin`.

Порядок чтения доков: `docs/user/develop/basic/{index,tool,config,publish}.md` → `docs/user/develop/framework/{index,service,events}.md` → `docs/cookbook/extension-cookbook.md` → `docs/cookbook/adding-a-tool.md` → `apps/cli/reference/README.md`.
