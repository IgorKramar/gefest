# Гефест (gefest)

Оркестратор Claude Code-агентов (ADR-0001) и экспертная база по **DeepSeek Harness (DSH)** и **yao (Yao Agents)** + архитектурный контур **собственного оркестратора Claude Code-агентов** (см. [ARCHITECTURE.md](ARCHITECTURE.md), [ADR-0001](docs/architecture/decisions/0001-sobstvennyj-orkestrator-claude-code.md)).

## Состав

| Файл | Что внутри | Источник |
|---|---|---|
| `docs/01-obzor-dsh.md` | что такое DSH, архитектура сверху, профили, быстрый старт | веб-обзоры + офсайт |
| `docs/02-ekosistema-plaginov.md` | CLI управления плагинами, «обязательный минимум», категории | веб-обзоры |
| `docs/03-arhitektura-yadra.md` | ядро Cordis, fiber/сервисы/события, профили и бандлы, agent presets, агентный цикл, сессии, конфигурация, карта монорепы | исходники |
| `docs/04-plaginy-iznutri.md` | анатомия плагина, манифест `dsh.*`, patch-файлы, карта регистраций, `dsh plugin`, Python SDK, расширение Web UI, чек-лист своего плагина | исходники |
| `docs/05-katalog-ekosistemy.md` | каталог топика `dsh-plugin` (~8 800 репо, топ-500 по звёздам), категории, тренды | GitHub API |
| `docs/06-yao-iznutri.md` | yao изнутри: раннер Claude Code, песочницы, задачи, доставка, A2O — карта заимствований | исходники |
| `reference/deepseek-harness/` | shallow-клон исходников DSH (в git не входит) | github.com/deepseek-ai/deepseek-harness |

## Три факта, которые чаще всего путают

- **Профиль ≠ agent preset.** Профили — `web`/`headless` (композиция процесса); Standard/Code/Minimal/Creator — agent presets (композиция одного агента).
- **Патч заменяет весь `config` строки**, а не мержит поля.
- **`settings.yaml` не хранит ключей** — только ссылки на credential store (`~/.dsh/.credentials.yaml`).

## Обновление клона

```sh
cd reference/deepseek-harness && git pull --depth 1
```
