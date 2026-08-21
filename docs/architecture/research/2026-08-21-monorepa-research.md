# Research digest: организация монорепы (D-17)

- Дата: 2026-08-21 · Шесть тем; выжимка, полный отчёт — в истории цикла.

## Headline

Раскладка `crates/*` + `web/` + `infra/` + `tests/contract` + `docs/` — текущий мейнстрим (живые примеры: Ryot, Komodo, rustzen-admin). Консенсус: «крейтов немного, границы стабильные» — 5–7 для этого размера норма, cargo-hakari не нужен.

## Ключевые факты по темам

1. **Workspace:** `workspace.dependencies` + `workspace.lints` + `edition = "2024"` в корне — обязательная база; ловушка edition 2024 — наследуемая зависимость не может сузить `default-features`, если workspace-декларация не сузила. Бинарь `hef` — тонкий (main + clap), иначе любая правка пересобирает линковку; `core` без tokio/axum — почти не пересобирается; главный анти-паттерн — «крейт-звезда» (толстеющий core); query-макросы sqlx — только в `db`. Профилировать `cargo build --timings`, не верить нарезке на слово.
2. **sqlx 0.9 (05.2026, переехал в transact-rs):** `.sqlx` — один, в корне workspace, `cargo sqlx prepare --workspace`; в CI `prepare --check --workspace` — единственный автоматический сторож «агент поменял запрос и забыл перегенерить». Грабли: `SQLX_OFFLINE=true` в `.env` ломает сам prepare (#3836) — флаг только в CI; sqlx-cli пиновать `--locked`; в 0.9 динамические SQL-строки требуют `AssertSqlSafe`.
3. **Статика:** `axum-embed` мёртв (2023). Живое: **static-serve 0.6.3** (07.2026, axum 0.8, компайл-тайм gzip/zstd, ETag, immutable для hashed) — лучшее совпадение; запасной — rust-embed 8.12 (+свой handler ~40 строк). Правила: hashed-ассеты `immutable`, `index.html` `no-cache`; сборка падает громко, если `web/dist` пуст (rust-embed молчит по умолчанию!). Порядок: `bun run build` → `cargo build`.
4. **Docker:** cargo-chef жив (0.1.77, 03.2026) и нужен именно на эфемерных раннерах GHA (mount-кэши BuildKit там не живут, слои chef экспортируются через `type=gha`); Dockerfile — `infra/Dockerfile`, контекст от корня; `.dockerignore`: `target/`, `web/node_modules`, `web/dist`. sccache — отложить.
5. **Примеры:** Ryot (crates/+apps/+libs/), Komodo (bin/+lib/+ui/), rustzen-admin (backend/+frontend/) — фронт одним верхнеуровневым каталогом и `crates/*` у axum-проектов — общепринято.
6. **Раннер задач:** just 1.58 (08.2026) зрел, смены моды нет; **но** just не умеет параллельные рецепты (dev-режим «vite + bacon одновременно» — через шелл), а **mise tasks** умеет параллелизм и watch нативно и уже наследует тулчейн/env (mise — менеджер владельца). cargo-make исчез из обсуждений; `cargo-watch` не поддерживается — брать **bacon**. Держать оба раннера — гарантированный дрейф: один, и тот же в CI.

## Caveats

Гранулярность — из принципа «крейт = единица инвалидации», не из бенчмарков; zstd-поддержку браузерами и brotli-статус static-serve перепроверить при внедрении; rmcp — внутри `api`, отдельный крейт не исследовался (не нужен на этом объёме).

## Sources

20 позиций с датами — в отчёте research-агента; ключевые: sqlx discussion #4271 (0.9, 05.2026) и issue #3836; corrode.dev compile times (03.2026); docs.rs/static-serve 0.6.3; cargo-chef releases 0.1.77; just releases 1.58; mise.jdx.dev/tasks; github: IgnisDa/ryot, moghtech/komodo.

*Terminology pass: проза русская; идентификаторы (`workspace.dependencies`, `workspace.lints`, `cargo sqlx prepare --workspace`, `.sqlx`, `AssertSqlSafe`, static-serve, rust-embed, cargo-chef, bacon, justfile, mise tasks, `type=gha`) без перевода.*
