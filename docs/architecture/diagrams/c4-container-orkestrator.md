# C4 (container): Гефест — оркестратор Claude Code-агентов

Состояние: цель после Ф1–Ф2 (ADR-0001), обновлено под ADR-0006…0010. Прослойка CLI — модуль внутри раннера (L3, на container-уровне не выделяется). Топология хостов и сети — `deployment-perimetr.md`; здесь — приложение.

```mermaid
graph TB
    Owner["Владелец<br/>(браузер / PWA с телефона)"]

    subgraph Tailnet["Периметр: tailnet (Headscale) — публичного endpoint нет (ADR-0010)"]
        subgraph Host["РФ-VM (docker-compose)"]
            Panel["<b>Панель + owner-API</b> — axum (Rust), фронт React 19 + Vite 8<br/>листенер только на Tailscale-IP, вход по passkeys<br/>доска задач, чат агентов (ADR-0011), детекторы,<br/>документы CM6-редактором (Ф2, ADR-0013), каталог ресурсов"]
            MCP["<b>MCP-листенер</b> — тот же бинарь<br/>только IP контейнерного моста;<br/>авторизация scoped-токеном задачи;<br/>pull чата на границах хода (ADR-0011)"]
            Runner["<b>Раннер-супервизор</b> — Rust (tokio), тот же бинарь<br/>владеет процессами; писатель stdin;<br/>каузальный delivered (ADR-0007);<br/>брокер комплектов: worktree, dev-БД клоном,<br/>секреты, git-токен из пула (ADR-0006/0010);<br/>внутри — прослойка CLI (ADR-0009)"]
            DB[("<b>Postgres</b><br/>задачи · журнал (append-only) · команды ·<br/>сессии/вехи · документы · память ·<br/>секреты (pgcrypto, ключ вне БД)")]
            A1["<b>Контейнер задачи №1</b> (rootless)<br/>claude -p --resume"]
            AN["<b>Контейнер задачи №N</b> (rootless)"]
        end
    end

    HB["Внешний heartbeat<br/>(healthchecks-класс)"]
    Alerts["Каналы алертов<br/>Telegram · ntfy · почта"]
    Git["GitHub / GitLab<br/>(мержи, пайплайны)"]
    Anthropic["API Anthropic<br/>(подписка Max, OAuth)"]
    Backup["S3 РФ-провайдера<br/>(pg_dump, шифрован)"]

    Owner -- "HTTPS через tailnet: WebAuthn, команды" --> Panel
    Panel -- "SQL: проекции, запись команд" --> DB
    Runner -- "SQL: claim команд, вехи инкрементально" --> DB
    Runner -- "spawn/stop (SIGTERM), stdin/stdout stream-json" --> A1
    Runner -- "spawn/stop, stdin/stdout stream-json" --> AN
    A1 -- "HTTP: инструменты Гефеста (inbox, вопросы)" --> MCP
    MCP -- "SQL: события своей сессии (интерим D-16)" --> DB
    A1 -- "git push / MR" --> Git
    AN -- "git push / MR" --> Git
    A1 -- "HTTPS через exit node EU (split-egress)" --> Anthropic
    AN -- "HTTPS через exit node EU" --> Anthropic
    Runner -- "ping ≤ 5 мин" --> HB
    Runner -- "факт+ссылка, без текста (C-3)" --> Alerts
    DB -- "pg_dump ежесуточно" --> Backup
    Panel -. "HTTPS API: детекторы статус ↔ факт мержа/CI" .-> Git
```

Panel, MCP и Runner — один деплоймент-юнит (один Rust-бинарь, ADR-0004); показаны раздельно, потому что слушают разные интерфейсы и несут разные поверхности доверия. Внутренняя организация бинаря по крейтам — `c4-component-binar.md` (ADR-0014).
