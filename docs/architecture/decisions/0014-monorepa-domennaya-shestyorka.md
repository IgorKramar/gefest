# ADR-0014: Монорепа — доменная шестёрка крейтов, mise tasks, embed-статика за флагом, образ из GHCR

- **Date**: 2026-08-21
- **Status**: Accepted
- **Authors**: Игорь (владелец); deep-цикл D-17
- Артефакты цикла: `../research/2026-08-21-monorepa{,-research,-design,-decision}.md`; roast — `../reviews/2026-08-21-roast-monorepa/00-summary.md`

## Context

Перед первым кодом (GF-5/GF-2) — раскладка репозитория: пути врастают в CI, sqlx-метаданные, Docker-контексты и инструкции агентов. Владелец: workspace по доменам; `hef` подкомандами; embed статики ради атомарности; `crates/*`+`web/`+`infra/`; mise tasks (раунд 2: параллельный dev, ноль новых инструментов); контрактные тесты верхнеуровнево; образ исполнителя в этом же репо. Research (6 тем): раскладка — мейнстрим (Ryot, Komodo); «5–7 крейтов норма, дальше не дробить»; `.sqlx` в корне с `prepare --check`-сторожем; static-serve вместо мёртвого axum-embed; cargo-chef для эфемерных раннеров GHA; bacon вместо cargo-watch. Roast (5 ролей, 37 находок, 8 high) выбор не оспорил; вердикт «Apply and proceed»; CC-1…CC-10 закрыты ред. 2; владелец подтвердил: образ из GHCR, интерим «SQL меняет владелец», флаг `embed-static`.

## Decision

- **Раскладка:** `crates/{core,db,runner,api,hef,fake-executor}` + `web/` + `infra/` + `tests/contract/` + `docs/`; граф (→ = зависит от): `hef`→`api`→`runner`→`db`→`core`; `fake-executor`→`core`. Канон «куда класть код» — один файл (ARCHITECTURE.md), остальные ссылаются.
- **Границы:** `core` — типы/перечисления-истина/ошибки; `sqlx` в нём — optional feature (включает только `db`); CI-сторож чистоты дефолтного графа `core`; чистые переходы машин состояний разрешены. `api` — модулен по доменам (documents/chat/mcp/views) с первого дня; распухший модуль — кандидат в седьмой крейт. Query-макросы и migrations — только в `db`. `hef` — тонкий бинарь (clap); дверь `hef remote` — «не тянет server-фичи».
- **Workspace:** edition 2024, `workspace.dependencies` (`default-features = false` минимум для sqlx/tokio — ловушка наследования фич), `workspace.lints`; фичи sqlx: `runtime-tokio`, `tls-rustls`, `postgres`, `uuid`, `time`, `migrate`, `json`.
- **sqlx-цикл:** `.sqlx` в корне, `prepare --workspace`; CI-сторож `prepare --check` (Postgres-service); `SQLX_OFFLINE=true` — только в CI-env (sqlx#3836); версия sqlx-cli — из `mise.toml`. Агентский цикл: dev-БД со схемой Гефеста — из комплекта брокера (ADR-0006); **интерим до брокера: SQL меняет только владелец**; runbook — в README `db`.
- **Статика:** `bun run build` → embed в `api` (static-serve; hashed `immutable`, `index.html` `no-cache`; пустой dist валит сборку проверкой в `build.rs`); **feature-флаг `embed-static`**: dev/test/rust-job — выключен, docker-job/релиз — включён; полный embed — в merge-queue/nightly; порядок bun→cargo — зависимостью mise-задач.
- **Раннер задач:** mise tasks (dev = vite-прокси + bacon параллельно; пины Rust и инструментов в `mise.toml`; тот же раннер в CI). justfile не заводится.
- **Docker/деплой:** `infra/Dockerfile` (bun → cargo-chef → slim); **прод-образ собирает CI → приватный GHCR; `deploy.sh` = `compose pull && up -d`** (сборки на прод-VM нет — линковка не конкурирует с живыми сессиями); `.dockerignore` расширен (`.git/`, `.env*`, `reference/`, `docs/`, ключи); секреты сборки — `--mount=type=secret`; образ исполнителя — `infra/executor-image/`, без кредов в слоях, хранение — тот же GHCR.
- **CI-фильтры:** rust-job = `crates/**` + корневые `Cargo.toml`/`Cargo.lock` + `.sqlx/**`; contract-job = `tests/contract/**`+`crates/{runner,fake-executor,core}/**`+`infra/executor-image/**` (бамп пина CLI гоняет контракт конструкцией — ворота ADR-0009 CC-8); infra-job на `infra/**`; фильтрация внутри job-а (required-совместимость); nightly/merge-queue — без фильтров; новый каталог = правка фильтров тем же PR.
- **Контракт:** типы stream-json — в `core`, но `fake-executor` эмитит сырые JSONL-фикстуры (литеральные строки, включая невалидные) — контракт не вырождается в roundtrip своих структур.
- **Гигиена:** `.gitignore` с `.env*` в скелете («в `.env` — только локальный dev-DSN»); `Cargo.lock` в git; экшены GHA — по SHA; `cargo deny` — отложено записью; TS-типы для `web/` — только генерацией из Rust со сторожем (при открытии двери второго JS-пакета).
- **Фазировка скелета — три PR:** (1) workspace+крейты+`mise.toml`+CI+гигиена+runbook; (2) dev-контур+флаг; (3) Dockerfile+GHCR (= GF-6).

## Consequences

**Положительные.** Границы видны агенту из имени крейта; слепых зон CI нет по построению; сторожа (`--check`, чистота `core`, nightly без фильтров) ловят дрейф машинно, а не памятью; деплой не грузит прод-VM; embed-налог снят с итераций.

**Отрицательные (приняты).** Горячий корневой Cargo.toml (зависимости — владелец отдельным PR); static-serve bus factor ≈ 1 (запасной rust-embed, триггер миграции назван); chef инвалидируется любым Cargo.toml; общий кэш-бюджет GHA — тихая деградация (присмотр по признакам); интерим сужает автономию агентов по SQL до брокера; скелет — честные 15–25 ч тремя PR.

**Нейтральные.** Седьмой крейт, генератор TS-типов, `hef-client` — двери с названными границами; нарезка профилируется `--timings` при жалобах, слияние дёшево.

## Alternatives considered

- **B. Компактная тройка** (`gefest`+`core`+`fake-executor`) — отклонена: границы дисциплиной модулей слабее для агентов, инкрементальная сборка хуже.
- **C. Мелкозернистая (8+)** — отклонена: нарушает «дальше не дробить», каскады пересборок от прок-макросов.
- **D. `backend/`+`frontend/` без workspace** — отклонена: ни границ, ни path-фильтров; переезд потом — переименование всего.
- Не рассматривались (обоснование в design): cargo-hakari (нулевой выигрыш на 6 крейтах); nx/Turborepo/Bazel-класс (кэш графа JS-пакетов не нужен при одном пакете; герметичность Bazel окупается на масштабе, которого нет — граница пересмотра в decision §4); отдельные репозитории; Bun workspaces (один пакет); just+mise одновременно (дрейф).

## Review trail

- 2026-08-21 — Roast, 5 ролей, 37 находок (8/19/10), «Apply and proceed» — [каталог](../reviews/2026-08-21-roast-monorepa/00-summary.md); закрыто ред. 2 decision.
- 2026-08-21 — Meta-review каталога: конформен (все Pass); M-2 поправлен, M-1 закрыт ред. 2, M-3…M-6 приняты/косметика.
- Ревью реализации — `/architect:review` после PR-1 скелета (GF-5).

*Terminology pass: проза русская; идентификаторы (`crates/*`, `workspace.dependencies`, `workspace.lints`, `.sqlx`, `prepare --check`, `SQLX_OFFLINE`, static-serve, `embed-static`, `build.rs`, cargo-chef, GHCR, mise tasks, bacon, clap, JSONL, ts-rs/specta, CC-N, B-N/H-N/J-N/C-N/F-N, D-N, GF-N, ADR-NNNN) без перевода; заголовки — verbatim Nygard.*
