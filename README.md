# Гефест (gefest)

**Самостоятельный оркестратор команды Claude Code-агентов.** Один владелец ставит задачи, видит живые статусы, отдаёт указания с подтверждаемой доставкой и подтверждает решения — из панели на втором мониторе или с телефона. Имя — по кузнецу с золотыми автоматонами, первыми разумными помощниками в литературе; CLI называется `hef`.

Репозиторий — единственное место, где живёт всё: архитектура, решения, задачи и исследовательская база. Vault для Гефеста не используется с первого дня ([ADR-0002](docs/architecture/decisions/0002-gefest-s-nulya-bez-vault.md)).

## Состояние

**Фаза Ф0.5 (архитектурная) пройдена — кода пока нет.** Принято 15 ADR, ядро решений закрыто, путь к первому коду открыт.

| | |
|---|---|
| Ближайшая работа | [GF-5](docs/tasks/GF-5-migracii-v1-yadra.md) — скелет монорепы и миграции v1-ядра; затем [GF-2](docs/tasks/GF-2-runner-supervizor.md) (раннер) и [GF-6](docs/tasks/GF-6-infrastruktura-perimetra.md) (периметр) |
| Открытые решения | D-11 (детекторы), D-13 (bootstrap задач), D-14 (вывод из Supabase), D-15 (задачная модель), D-16 (MCP-поверхность) — см. [карту решений](docs/architecture/decision-map.md) |
| Стек | Rust (axum, tokio, sqlx, rmcp) одним бинарём + React 19 / Vite 8; Postgres; docker-compose на двух хостах |

## С чего начать

| Документ | Зачем |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Главный вход: сводка системы, индекс решений, атрибуты качества, ограничения, анти-паттерны. Канон «куда класть код» — здесь, остальные документы ссылаются, а не дублируют |
| [CONCEPTS.md](CONCEPTS.md) | Словарь проекта: сторож, дверь, интерим-регламент, указание, каузальный delivered, комплект брокера |
| [docs/architecture/decisions/](docs/architecture/decisions/) | ADR с индексом в [README](docs/architecture/decisions/README.md) — пятнадцать принятых решений |
| [docs/architecture/decision-map.md](docs/architecture/decision-map.md) | Открытые решения (D-N), их зависимости и порядок циклов |
| [docs/tasks/](docs/tasks/) | Задачи (GF-N) с доской в [README](docs/tasks/README.md) — единственное место учёта работ |
| [docs/design/](docs/design/) | Нормативные ТЗ облика: [веб-панель](docs/design/tz-web-panel.md), [мобильный PWA](docs/design/tz-mobile-pwa.md) |
| [docs/solutions/](docs/solutions/) | Learnings проекта |

Диаграммы — в [docs/architecture/diagrams/](docs/architecture/diagrams/): контекст и контейнеры (C4), компоненты бинаря, развёртывание периметра, машины состояний сессии и указания, ER-схема v1-ядра.

## Что решено

Пятнадцать ADR складываются в такую систему.

- **Свой тонкий оркестратор вместо готовых платформ** ([0001](docs/architecture/decisions/0001-sobstvennyj-orkestrator-claude-code.md)): DSH не умеет Claude Code как полноценного члена команды, yao требует подписочных кредов внутри стороннего продукта. Пишется с нуля ([0002](docs/architecture/decisions/0002-gefest-s-nulya-bez-vault.md)), agent-dashboard остаётся страховкой до паритета.
- **Данные** ([0005](docs/architecture/decisions/0005-shema-dannyh-zhurnal-plus-state.md)): «журнал плюс материализованное состояние» — append-only поток и state-таблица одной транзакцией с CAS. v1-ядро — 14 таблиц, RLS включается сразу. Канон памяти — тоже в Postgres ([0003](docs/architecture/decisions/0003-kanon-pamyati-postgres-pgvector-dver.md)).
- **Доставка** ([0007](docs/architecture/decisions/0007-dostavka-ukazanij-push-delivered.md)): раннер владеет stdin процесса и пишет туда напрямую, а `delivered` — каузальный: подтверждается активностью, причинно связанной с вручением, а не фактом записи. Это лечит боль «команда отправлена, но не дошла».
- **Исполнители** ([0006](docs/architecture/decisions/0006-izolyaciya-konteiner-na-zadachu.md)): rootless-контейнер на задачу; раннер — брокер ресурсов, секреты живут только у него и умирают вместе с контейнером. Сессии ([0008](docs/architecture/decisions/0008-sessii-vehi-ukazateli-v-syryo.md)) хранят вехи с указателями в сырьё, общение с CLI изолировано одной прослойкой ([0009](docs/architecture/decisions/0009-prosloika-cli-uuid7-kontraktnye-testy.md)).
- **Периметр** ([0010](docs/architecture/decisions/0010-perimetr-dva-hosta-passkeys-broker.md)): российская VM с данными плюс европейский VPS с exit node; через него уходят только домены Anthropic. Панель не смотрит в интернет — Tailscale и passkeys.
- **Взаимодействие и содержимое**: чат потоком с курсорами и mailbox с push ([0011](docs/architecture/decisions/0011-chat-potok-kursory-mailbox-inbox.md)); документы на CodeMirror 6, frontmatter — источник метаданных ([0013](docs/architecture/decisions/0013-dokumenty-cm6-atomic-frontmatter-vidy.md)).
- **Разработка**: монорепа из шести крейтов ([0014](docs/architecture/decisions/0014-monorepa-domennaya-shestyorka.md)), GitHub Actions с PR-воротами ([0012](docs/architecture/decisions/0012-ci-github-actions-pr-vorota.md)), облик «тёмная кузница» ([0015](docs/architecture/decisions/0015-dizajn-paneli-kuznitsa.md)) — огненная шкала зарезервирована за активностью, поэтому взгляд мгновенно находит работающего агента.

## Как здесь принимаются решения

Открытое решение получает номер `D-N` в карте решений и проходит цикл **discovery → research → design → decision**; крупные — ещё и **roast** пятью независимыми ролями (devil-advocate, pragmatist, junior-engineer, compliance-officer, futurist), затем meta-review на соответствие шаблонам. Артефакты циклов сохраняются в [research/](docs/architecture/research/) и [reviews/](docs/architecture/reviews/) целиком — вместе с отклонёнными альтернативами и найденными атаками.

Принятое решение уезжает в ADR и вычёркивается из карты. **Принятый ADR не переписывается** — при изменении по существу пишется новый, отменяющий старый; в теле допустимы только пометки-уточнения. Так сохраняется след эволюции мышления, а не только его результат.

Правила, которые проект применяет к себе:

- **Готово = мерж плюс зелёная проверка.** Прекращение не равно завершению.
- **Дверь** — точка расширения с названным триггером открытия и бюджетом, чтобы не дрейфовала в умолчание.
- **Интерим-регламент** записывается вместе с условием снятия; сужение автономии без условия снятия считается дырой, а не регламентом.
- **Сторож против невозможности**: автоматическая проверка легитимна, только если у каждого класса участников есть честный путь до зелёного внутри своего периметра ([learning](docs/solutions/best-practices/storozh-protiv-nevozmozhnosti.md)).
- Пассивных триггеров пересмотра не бывает — только календарные задачи с владельцем.

## Экспертная база

Исследование доноров, по образцам которых проектируется Гефест. Заимствуются решения, не код и не зависимости.

| Файл | Что внутри | Источник |
|---|---|---|
| [01](docs/01-obzor-dsh.md) | что такое DSH, архитектура сверху, профили, быстрый старт | веб-обзоры и офсайт |
| [02](docs/02-ekosistema-plaginov.md) | CLI управления плагинами, «обязательный минимум», категории | веб-обзоры |
| [03](docs/03-arhitektura-yadra.md) | ядро Cordis: fiber, сервисы, события, профили и бандлы, agent presets, агентный цикл, сессии, карта монорепы | исходники |
| [04](docs/04-plaginy-iznutri.md) | анатомия плагина, манифест `dsh.*`, patch-файлы, карта регистраций, Python SDK, расширение Web UI | исходники |
| [05](docs/05-katalog-ekosistemy.md) | каталог топика `dsh-plugin` (около 8 800 репозиториев, топ-500 по звёздам), тренды | GitHub API |
| [06](docs/06-yao-iznutri.md) | yao изнутри: раннер Claude Code, песочницы, задачи, доставка, A2O — карта заимствований | исходники |

### Три факта, которые чаще всего путают

- **Профиль не равен agent preset.** Профили — `web` и `headless` (композиция процесса); Standard, Code, Minimal, Creator — agent presets (композиция одного агента).
- **Патч заменяет весь `config` строки**, а не сливает поля.
- **`settings.yaml` не хранит ключей** — только ссылки на credential store (`~/.dsh/.credentials.yaml`).

### Клоны исходников

Каталог `reference/` (клоны deepseek-harness и yao) в git не входит — это учебный материал, восстанавливаемый по требованию.

```sh
cd reference/deepseek-harness && git pull --depth 1
```
