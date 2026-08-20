# C4 (container): Гефест — оркестратор Claude Code-агентов

Состояние: цель после Ф1–Ф2 (ADR-0001). Обновлять при изменении топологии. Прослойка CLI — модуль внутри раннера (компонент L3, на container-уровне не выделяется).

```mermaid
graph TB
    Owner["Владелец<br/>(браузер / PWA с телефона)"]

    subgraph VPN["Периметр: VPN/mesh (WireGuard/Tailscale) — публичного endpoint нет"]
        subgraph Host["Сервер (docker-compose)"]
            Panel["Панель — Starlette + React<br/>доска задач, детекторы расхождений,<br/>документы (wiki-линки, русский FTS)"]
            DB[("Postgres<br/>задачи · журнал (append-only) ·<br/>команды · документы · память")]
            Runner["Раннер-супервизор — Python (asyncio)<br/>владеет процессами исполнителей;<br/>идемпотентная доставка (delivered);<br/>переподхват после рестарта;<br/>внутри — прослойка CLI (модуль):<br/>флаги, stream-json, ~/.claude, health-check кредов"]
            A1["claude -p --resume<br/>исполнитель №1 (worktree)"]
            AN["claude -p --resume<br/>исполнитель №N"]
        end
    end

    HB["Внешний heartbeat<br/>(healthchecks/Telegram)"]
    Git["GitHub / GitLab<br/>(мержи, пайплайны)"]
    Anthropic["API Anthropic<br/>(подписка Max, OAuth)"]
    Backup["Бэкап вне хоста"]

    Owner -- "HTTPS через VPN: просмотр, команды" --> Panel
    Panel -- "SQL: чтение проекций, запись команд" --> DB
    Runner -- "SQL: claim команд, запись событий стрима (инкрементально)" --> DB
    Runner -- "spawn/resume, stdin/stdout stream-json" --> A1
    Runner -- "spawn/resume, stdin/stdout stream-json" --> AN
    A1 -- "git push / MR, HTTPS+SSH" --> Git
    AN -- "git push / MR, HTTPS+SSH" --> Git
    A1 -- "HTTPS: LLM-запросы (OAuth подписки)" --> Anthropic
    AN -- "HTTPS: LLM-запросы (OAuth подписки)" --> Anthropic
    Runner -- "HTTPS: ping каждые ≤5 мин" --> HB
    DB -- "pg_dump по крону, ежесуточно" --> Backup
    Panel -. "HTTPS API: детекторы сверяют статус ↔ факт мержа/CI" .-> Git
```
