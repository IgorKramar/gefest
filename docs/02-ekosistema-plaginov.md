# Экосистема плагинов DSH

Собрано 2026-08-20 из обзоров (atlascloud.ai, scriptbyai.com, orcarouter.ai) и каталогов.

## Масштаб

За два дня после релиза — 2000+ заявок; в community-списках 1100+ устанавливаемых плагинов в 14 категориях, каталоги индексируют до 6600+.

## Управление плагинами (CLI)

```bash
dsh plugin --profile web add <package>              # из npm
dsh plugin --profile web add "github:owner/repo#ref" # из GitHub
dsh plugin --profile web add "link:$(pwd)"           # локальная разработка
dsh plugin --profile web list                        # проверить установленное
npx -p @deepseek-ai/dsh dsh plugin --profile web add <pkg>  # без глобальной установки
```

`--profile` обязателен: профили решают, какой bundle плагинов получает сессия; `web` — профиль Web UI. После установки — перезапуск `dsh web` и обновление страницы. Плагин активен, только если в его package.json объявлен `dsh.bundle.patch` — без него пакет ставится, но остаётся мёртвым грузом.

## «Обязательный минимум» (подборка atlascloud)

| Плагин | Что делает |
| --- | --- |
| dshmarket | графический браузер плагинов в Settings, установка в один клик |
| dsh-find-plugin | агент сам ищет плагины в экосистеме |
| dsh-poison-guard | скан исходников плагина на вредонос перед установкой |
| dsh-plugin-doctor | проверка манифеста, сборки, здоровья установки |
| dsh-cost-meter | расходы за сессию, дневной бюджет, история |
| dsh-tier-router | двухуровневая маршрутизация: дорогая модель планирует, дешёвая исполняет |
| dsh-context | структура контекстного окна: откуда берутся токены |

**«Слой, который никто не перечисляет»** — конфигурация провайдера модели в `settings.yaml` (~9 строк YAML). Выбор маршрута (официальный API DeepSeek с почасовыми тарифами / хостед с фиксированной ставкой / локальный ollama) определяет экономику всего стека; без него остальные плагины лишь удорожают агента.

## Категории и заметные плагины (по scriptbyai, 40 шт.)

- **Интерфейс**: DSH Web UI (task board, git-граф, удалённый доступ, статистика токенов), DSH Better Sidebar, DSH TUI, DSH Tianshu TUI (TDD-контроль, evidence gates)
- **Зрение**: Modlens (скриншоты → OCR + структура), DSH Vision Router, DSH Vision Toolkit (длинные скриншоты, реконструкция UI)
- **Память**: Graph Memory (PageRank, community detection, векторный поиск), Mnemon, Engramory (человекочитаемые версионируемые файлы), DSH Noema, dsh-memento, dsh-memory-evolve, dsh-recall
- **Браузер/поиск**: DSH Browser (Chrome через нативный мост), ModSearch, AnySearch, Argo DSH (evidence-oriented research)
- **Агенты**: DSH Agent Teams (@nanmicoder/dsh-agent-teams) — группы специализированных агентов
- **Рантайм/файлы**: Mirage DSH (виртуальное workspace: локальные каталоги + удалённые ресурсы), SandBase Harness (managed-agents через MCP), DSH At File (@-упоминания файлов), Treg DSH (реестр инструментов + MCP-коннектор)
- **Компоненты**: DSH GenUI (интерактивные графики/диаграммы), DSH Visualize (sandboxed HTML-карточки)
- **Разработка плагинов**: DSH Super Injector (hot-reload локальных плагинов без рестарта)
- **Безопасность**: DSH Auto Mode (классификация разрешений перед выполнением инструмента)
- **Мониторинг**: Working Activity, DSH Context
- **Прочее**: темы (Transparent UI, Deep Whale, DSH Ads — ретро-портал 2000-х), питомцы (Whale Girl, DSH Pet, DSH Dafeiyu), DSH Notes, DSH Plugin Subscriptions (OAuth-логин ChatGPT/Claude/Grok), дизайн (iPolloWork Design Studio, DSH OpenPencil), голос (dsh-voice), workflow (dsh_workflow)

## Гигиена

- Пиновать версии: rc-релизы ломают совместимость.
- Community-инструменты: plugin-registry, dsh-plugin-check.
- Перед установкой стороннего плагина — dsh-poison-guard: плагины исполняют код в рантайме агента.
