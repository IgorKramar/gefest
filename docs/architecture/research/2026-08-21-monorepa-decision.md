# Decision summary: организация монорепы (D-17)

- Дата: 2026-08-21 · Фаза: Decide (deep) · Входы: discovery (2 раунда, Q1–Q8), research (6 тем), design (A/B/C/D + explicitly-not-considered)
- Легенда: «крейт» — единица компиляции cargo; «раннер задач» — командный раннер сборки (не путать с раннером-супервизором Гефеста); «сторож» — CI-проверка, падающая при рассинхроне артефактов.
- Статус: **принято владельцем** («Так-то я за А», 2026-08-21; nx/Bazel-вопрос отвечен: кэш графа JS-пакетов не нужен при одном пакете, Bazel-класс окупается на масштабе, которого нет — граница пересмотра названа в §4). Ожидает roast + ADR-0014.

## Reviews

(заполняется после roast)

## 1. Выбранная альтернатива

**A: доменная шестёрка крейтов** + общая часть design:

1. **Раскладка:** `crates/{core,db,runner,api,hef,fake-executor}` + `web/` + `infra/` + `tests/contract/` + `docs/`. Граф: `core` ← `db` ← `runner` ← `api` ← `hef`; `fake-executor` → `core`. Правило против «крейта-звезды»: в `core` — только типы/перечисления-истина/ошибки, без поведения, без tokio/axum. Все query-макросы sqlx — только в `db`; migrations/ — внутри `db` (`sqlx::migrate!`); rmcp — внутри `api`.
2. **Workspace-база:** `edition = "2024"`, `workspace.dependencies` (`default-features = false` где нужна гибкость — ловушка edition 2024), `workspace.lints` в корне.
3. **sqlx:** `.sqlx` в корне, `cargo sqlx prepare --workspace`; CI: сборка с `SQLX_OFFLINE=true` (env CI, не `.env` — #3836); отдельный job: Postgres-service → `migrate run` → `prepare --check --workspace` (сторож за агентами); sqlx-cli пинован `--locked`.
4. **Статика:** `bun run build` → `web/dist` → embed в `api` через **static-serve** (компайл-тайм gzip/zstd, ETag; hashed — `immutable`, `index.html` — `no-cache`); пустой `dist` валит сборку громко; запасной путь — rust-embed + свой handler.
5. **`hef`** — тонкий бинарь: main + clap-подкоманды (`serve`, `migrate`, …); клиентские `hef remote …` — дверь.
6. **Раннер задач — mise tasks** (Q8): параллельный dev (`vite dev` + bacon), наследование тулчейна/env, тот же раннер в CI; justfile не заводится (дрейф двух раннеров).
7. **Docker:** `infra/Dockerfile` (bun-стадия → cargo-chef → slim runtime), контекст от корня, `.dockerignore` (`target/`, `web/node_modules`, `web/dist`); кэш GHA — слоями chef (`type=gha`). Образ исполнителя — `infra/executor-image/` (пин CLI + контрактные тесты — один PR, ADR-0009).
8. **Контрактные тесты** — `tests/contract/` (верхний уровень), path-фильтр: гоняются при изменении `runner`/`fake-executor`/самих тестов.

## 2. Почему

Раскладка — мейнстрим живых axum+React-проектов (Ryot, Komodo); шестёрка — верхняя граница research-консенсуса «5–7, дальше не дробить», и границы по каталогам работают на главную особенность проекта — агентов-коммиттеров, которым «куда класть код» должно быть видно из имени крейта; mise уже стоит тулчейн-менеджером — раннер задач достаётся без нового инструмента; каждый выбор внутри (static-serve, cargo-chef, `.sqlx`-корень) — по свежему research с датами.

## 3. Что отдаём

Церемония шести Cargo.toml (смягчена `workspace.dependencies`); static-serve без brotli (zstd/gzip достаточно, перепроверить при внедрении); cargo-chef инвалидирует recipe при правке любого Cargo.toml (редко на 6 крейтах); нарезка не бенчмаркалась — принято правило «профилировать `cargo build --timings` при первых жалобах на сборку»; mise tasks моложе just как раннер (смягчение — рецепты тривиальны, переезд на just — механический).

## 4. Границы пересмотра

Второй прод-сервис + пересборка дольше ~10 мин + второй разработчик → переоценка оркестратора сборки (Bazel-класс/nx); жалобы на инкрементальную сборку → `cargo build --timings` и пересмотр нарезки (слияние — дешёвая операция); static-serve мертвеет/нужен brotli → rust-embed-запасной; появление второго JS-пакета (например, общие TS-типы из Rust-схем) → Bun workspaces тем же PR.

## 5. Операционные последствия

GF-5 стартует в этой раскладке (первые крейты: `core`, `db` + миграции; workflow CI из ADR-0012 кладётся вместе с ними); `infra/` наполняется в GF-6; `mise.toml` с задачами `dev`, `build`, `check`, `test`, `sqlx-prepare`, `docker` — первым PR. Path-фильтры CI: `crates/**` → rust-job, `web/**` → front-job, `crates/db/migrations/**` → migrations-job, `tests/contract/**`+`crates/runner/**` → contract-job.

## 6. Критерий выполненности

ADR-0014 принят; скелет раскладки (workspace + пустые крейты с зависимостями + mise.toml + CI) — первый PR GF-5, прошедший собственные ворота.
