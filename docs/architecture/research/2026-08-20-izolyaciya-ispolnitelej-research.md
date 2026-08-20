# Research digest: per-task песочницы исполнителей (D-3)

Дата: 2026-08-20 (агент-исследователь; standard-цикл).

## Question

Rootless-контейнеры под Rust-управлением против bwrap/Landlock; эфемерные чистые Postgres-БД; housekeeping без висящих.

## Headline finding

Мейнстрим 2026: **podman rootless + REST API** (крейт `bollard` 0.21 поддерживает podman first-class с автодискавери rootless-сокета) для тяжёлой изоляции; **bubblewrap — проверенная лёгкая альтернатива, которой пользуются сами Claude Code (bwrap + socat + прокси с allowlist доменов) и OpenAI Codex (bwrap + Landlock + seccomp)**. Для БД — `CREATE DATABASE ... TEMPLATE` на общем Postgres: **~10–40 мс на клон**, контейнер-per-task для БД не нужен. Housekeeping — labels + reaper (Ryuk-паттерн testcontainers) + TTL-sweep.

## Detailed findings

1. **Контейнеры**: bollard 0.21 — podman first-class (probes DOCKER_HOST → rootless podman → system podman → docker); rootless-сеть по умолчанию pasta. Старт — сотни мс на прогретом образе; ловушка: первый rootless-запуск с `--userns auto` до ~250× медленнее (chown слоёв) — прогревать. Лимиты CPU/RAM в rootless: только cgroups v2 + **systemd-делегирование** (`Delegate=cpu cpuset io memory pids` в user@.service.d — по умолчанию делегируются лишь memory/pids, проверить на хосте!).
2. **bwrap/Landlock**: Claude Code `/sandbox` = bwrap ФС + `--unshare-net` (только loopback) + socat-прокси наружу с фильтрацией доменов; Codex = bwrap + seccomp (сеть по syscall) + no_new_privs, Landlock как fallback. Зрелость высокая (Flatpak), но: (а) это **allowlist**-инструмент — задокументирован обход denylist через `/proc/self/root`; (б) готовой связки bwrap+pasta нет — «сеть с фильтрацией» = свой прокси-компонент; (в) **лимитов CPU/RAM у bwrap нет** — вешать процесс в systemd-scope (`systemd-run --user --scope -p MemoryMax= -p CPUQuota=`) отдельно.
3. **Эфемерные БД**: template-клон — 10–40 мс на шаблоне в десятки МБ (наш случай «схема+сиды»); ограничение — **никаких подключений к шаблону** в момент клона (реальные гонки — sqlx #1283) → раннер сериализует CREATE и никогда не коннектится к template; уборка — `DROP DATABASE ... WITH (FORCE)` (PG13+). Альтернативы (schema-per-task — слабее изоляция; pg_tmp — отдельный инстанс, избыточен; контейнер-per-task — никто не рекомендует) отклонены источниками.
4. **Housekeeping**: Ryuk-паттерн — label `task_id`+`created_at` на каждый ресурс, reaper держит связь с владельцем и убивает всё по label при разрыве (переживает crash раннера); второй слой — TTL-sweep «всё наше старше N минут»; исключения из reaper — источник зомби (172 zombie containers — задокументированный случай), только явные и считанные. Для bwrap housekeeping тривиален: process group + PDEATHSIG, мусора контейнеров нет.

## Caveats and unknowns

Числа латентности контейнеров — из сомнительных бенчей, мерить на хосте; bwrap+pasta связки нет — сеть только прокси-паттерном; «docker уже стоит → миграция на podman не обязательна, механика bollard идентична» — выбор рантайма допустимо отдать хосту; cgroup-делегирование проверить.

## Implications for the design phase

Обе ветки жизнеспособны и по-разному дороги: контейнеры дают изоляцию+сеть+лимиты+housekeeping одним зрелым механизмом (и дословный путь в поды — уточнённый триггер П-И1); bwrap-путь легче и «как у вендоров», но собирается из трёх самодельных частей (bwrap + systemd-scope + свой прокси) и требует allowlist-дисциплины. Эфемерные БД — решены: общий Postgres + template, из раннера, сериализованно.

## Sources

bollard docs.rs 0.21 + GitHub; podman_rest_client; podman issue #26479; rootlesscontaine.rs cgroup2; scrivano.org (2019, каноника); code.claude.com/docs/sandboxing; sambaiz.net №547; claudecodecamp (обход /proc/self/root); openai/codex codex-rs/linux-sandbox; simonwillison.net 2025-11-09; bubblewrap #366; pgtestdb; IntegreSQL; maragu.dk; sqlx #1283; eradman/ephemeralpg; testcontainers Ryuk (golang/dotnet docs); worldline.tech 2023-01; coffeesprout (zombie); обзорные daily.dev/last9 (SEO, ориентир). Даты — в отчёте исследователя.
