# ARCHITECTURE — Гефест, оркестратор Claude Code-агентов

Проект **Гефест** (`gefest`; имя — по мастеру с золотыми автоматонами, первыми разумными помощниками в литературе): база знаний по DSH/yao и архитектурный контур **собственного тонкого оркестратора** — управляющего контура (control plane) команды Claude Code-агентов. **Пишется с нуля в этом репозитории** (ADR-0002); agent-dashboard не переделывается — живёт страховкой до паритета, затем списывается. CLI — `hef`. Здесь живёт всё: код Гефеста, архитектура, решения, задачи (`docs/tasks/`, GF-N) и исследовательская база. Vault для Гефеста не используется (ADR-0002).

## Сводка системы

Один владелец управляет командой Claude Code-агентов (подписка Max 20x) через self-hosted панель: статусы в реальном времени, подтверждаемая постановка задач (в т.ч. с телефона поверх VPN), взаимодействие агентов, каноническое хранилище знаний и памяти (vault Obsidian выводится). Раннер владеет headless-процессами `claude -p --resume` (stream-json) — доставка подтверждаема по построению. Развёртывание — docker-compose на отдельной РФ-VM; европейский VPS несёт exit node (split-egress к Anthropic), Headscale и DERP (ADR-0010).

## Индекс решений

| ADR | Дата | Статус | Суть |
|---|---|---|---|
| [0012](docs/architecture/decisions/0012-ci-github-actions-pr-vorota.md) | 2026-08-21 | Accepted | GitHub Actions; PR-ворота для кода (агенты — только PR); деплой ручным скриптом; CD — дверь |
| [0011](docs/architecture/decisions/0011-chat-potok-kursory-mailbox-inbox.md) | 2026-08-21 | Accepted | Чат — поток с курсорами (pull), mailbox — инбокс (push); права по проекту; broadcast — только владелец |
| [0010](docs/architecture/decisions/0010-perimetr-dva-hosta-passkeys-broker.md) | 2026-08-21 | Accepted | Периметр: два хоста (РФ-VM + EU VPS со split-egress к Anthropic); Headscale-tailnet; passkeys; секреты pgcrypto; пул scoped-токенов |
| [0009](docs/architecture/decisions/0009-prosloika-cli-uuid7-kontraktnye-testy.md) | 2026-08-21 | Accepted | Прослойка CLI: UUIDv7 сессий из БД; грабли yao обойдены пакетом; контрактные тесты S3–S5; пин CLI в образе |
| [0008](docs/architecture/decisions/0008-sessii-vehi-ukazateli-v-syryo.md) | 2026-08-21 | Accepted | Сессии: единая машина состояний; вехи-указатели в сырьё; drill-down — срез raw через API; саммари на границах жизни |
| [0007](docs/architecture/decisions/0007-dostavka-ukazanij-push-delivered.md) | 2026-08-21 | Accepted | Push раннером в stdin; каузальный delivered; stop = SIGTERM с инвалидацией очереди; `requires_ack`-дверь с бюджетом |
| [0006](docs/architecture/decisions/0006-izolyaciya-konteiner-na-zadachu.md) | 2026-08-20 | Accepted | Контейнер-на-задачу; брокер ресурсов; секреты только у раннера |
| [0005](docs/architecture/decisions/0005-shema-dannyh-zhurnal-plus-state.md) | 2026-08-20 | Accepted | Журнал+состояние одной транзакцией; v1-ядро 14 таблиц; RLS с v1; gap-detection канала панели; trust-дверь D-16 |
| [0004](docs/architecture/decisions/0004-stek-rust-axum-react-vite.md) | 2026-08-20 | Accepted | Rust-бэкенд одним бинарём + React 19/Vite 8; Bun — toolchain; C-С1: idle-ресурсы = деньги |
| [0003](docs/architecture/decisions/0003-kanon-pamyati-postgres-pgvector-dver.md) | 2026-08-20 | Accepted | Канон памяти в Postgres; трёхслойный recall с бюджетами; владелец-редактор; pgvector-дверь по замеру; EverOS — донор идей |
| [0002](docs/architecture/decisions/0002-gefest-s-nulya-bez-vault.md) | 2026-08-20 | Accepted | С нуля в этом репо; AD — страховка, не фундамент; фиксация только здесь, без vault |
| [0001](docs/architecture/decisions/0001-sobstvennyj-orkestrator-claude-code.md) | 2026-08-20 | Accepted (amended by 0002) | Свой тонкий оркестратор вместо yao/DSH; Ф0 — доставка через владение процессом; Ф0.5 — проектирование по образцам yao/DSH |

## Структура (C4, container)

См. [c4-container-orkestrator.md](docs/architecture/diagrams/c4-container-orkestrator.md) (приложение) и [deployment-perimetr.md](docs/architecture/diagrams/deployment-perimetr.md) (хосты и сеть, ADR-0010). Компоненты: один Rust-бинарь (axum: owner-листенер на Tailscale-IP с passkeys + MCP-листенер на контейнерном мосту; tokio: раннер-супервизор; внутри — прослойка CLI) ↔ Postgres (append-only журнал, задачи, команды, вехи, память, секреты pgcrypto) → контейнеры задач `claude -p --resume` (egress к Anthropic — через exit node EU). Периметр — tailnet (Headscale). Внешние: GitHub/GitLab (факты мержей — «done = состояние внешнего мира»), heartbeat, алерт-каналы, S3-бэкап. Машины состояний: [state-sessiya.md](docs/architecture/diagrams/state-sessiya.md), [state-ukazanie.md](docs/architecture/diagrams/state-ukazanie.md); данные: [er-v1-yadro.md](docs/architecture/diagrams/er-v1-yadro.md).

## Атрибуты качества (принятая поза)

- Доступность: «работает, когда работает владелец» + автоперезапуск; обнаружение отказа раннера — ≤ 15 мин (внешний heartbeat, пинг ≤ 5 мин); недоступность панели не останавливает агентов.
- Консистентность: одна точка истины по статусу; расхождения видимы (детекторы), не молчаливы.
- Долговечность: журнал/задачи/знания не теряются никогда — pg_dump вне хоста ежесуточно (RPO ≤ 24 ч; события стрима пишутся в БД инкрементально, не батчем), проверенный restore — предусловие вывода vault.
- Безопасность: панель не в публичном интернете; матрица секретов; scoped git-токены агентам; аудит различает владельца и агентов.

## Ограничения (формально приняты)

- Исполнители — Claude Code по подписке Max, без API-токенов (C-Н1); вспомогательные LLM — бесплатные через OpenRouter.
- Биллинг сервера — по потреблению ресурсов (C-С1): резидентные процессы обязаны быть минимальными; лишние рантаймы в проде не заводятся (ADR-0004).
- Один оператор (F7): каждый компонент обязан выживать без присмотра.
- Один источник истины — общая память; личные памяти согласуются; vault выводится, привычки покрываются (C-Н5, С7). Для самого Гефеста vault не используется с первого дня: задачи, ADR, learnings — в этом репозитории (ADR-0002).
- Compose; Kubernetes — только при появлении причины (П-1).
- Авторство внешних артефактов — Игорь Крамарь, без упоминаний ИИ.

## Анти-паттерны (не предлагать снова)

- Подписочные креды внутри сторонних продуктов (yao и любых других) — запрещено Consumer Terms; путь возврата к платформам — только через границы пересмотра ADR-0001.
- Содержимое классов «карточка»/«журнал» и клиентских скоупов — в промпты внешних LLM (включая бесплатный OpenRouter) не отправляется никогда (ADR-0003).
- Agent SDK / Managed Agents как путь оркестрации — только API-ключ, против C-Н1.
- «Толстый» оркестратор: свои VNC-песочницы, мультимодельные исполнители, чат-клиент, свой CI — вне границы без отдельного ADR.
- Доставка «сигналом в чужой сокет» без владения процессом — источник боли №2, заменена Ф0.
- Пассивные триггеры пересмотра — только календарные задачи с владельцем.
- Секреты в песочницах исполнителей и в руках агентов — не живут: только инжекция комплектом от раннера на время задачи (ADR-0006); docker исполнителю не выдаётся.
- Обязательный ack на каждое указание — отвергнутая альтернатива C: `requires_ack` — точечная дверь с бюджетом (>2 классов = пересмотр D-4, ADR-0007), не общий режим.
- Тексты указаний/вопросов в алертах и внешних уведомлениях — никогда: только факт + ссылка (ADR-0007).
- Tailscale identity headers как аутентификация — подделываемы процессами хоста (контейнерами-исполнителями); auth владельца — только passkeys на owner-листенере (ADR-0010).
- Автовыдача git-токенов через API хостинга — «токен, создающий токены» у раннера не живёт: только ручной пул (ADR-0010).

## Открытые вопросы

- ~~Имя целевой системы~~ — решено 2026-08-20: **Гефест** (репо `gefest`, CLI `hef`).
- ~~Эволюция или с нуля~~ — решено 2026-08-20 (ADR-0002): с нуля; agent-dashboard не трогаем, его схема и детекторы — донорские образцы.
- ~~Хост~~ — решено 2026-08-21 (ADR-0010): отдельная РФ-VM (данные, 152-ФЗ) + европейский VPS (exit node + Headscale + DERP; split-egress к Anthropic — исполнители с российского IP не работают).
- ~~Слой памяти / EverOS / механизм подъёма~~ — решено 2026-08-20 (ADR-0003): Postgres-канон, владелец-редактор через панель, EverOS отклонён тремя блокерами.

## Карта репозитория

- `docs/01–02` — DSH по веб-источникам; `docs/03–04` — ядро Cordis и система плагинов DSH по исходникам; `docs/05` — каталог экосистемы; `docs/06` — yao изнутри (карта заимствований, готов).
- `docs/architecture/decision-map.md` — карта открытых решений (D-N) и порядок циклов.
- `docs/architecture/research/` — артефакты deep-цикла (discovery, research, design, decision) и observe-отчёты.
- `docs/architecture/reviews/` — roast-артефакты.
- `docs/architecture/decisions/` — ADR (индекс в README.md).
- `docs/tasks/` — задачи Гефеста (GF-N), доска в README.
- `reference/` — клоны deepseek-harness и yao (в git не входят, учебный материал).
