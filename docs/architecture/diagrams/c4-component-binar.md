# C4 (component): бинарь `hef` — крейты workspace (ADR-0014)

L3: внутренняя организация одного контейнера (прод-бинаря). Крейт = компонент; граф зависимостей — конституция ADR-0014 (→ = зависит от). `fake-executor` — тестовый бинарь, в прод не попадает; показан для полноты workspace.

```mermaid
graph TB
    Compose["docker compose<br/>(запуск на РФ-VM)"]

    subgraph Bin["Прод-бинарь hef (один процесс, один артефакт)"]
        Hef["<b>crates/hef</b><br/>main + clap-подкоманды<br/>(serve, migrate; дверь hef remote)"]
        API["<b>crates/api</b><br/>axum: owner-роутер (passkeys) +<br/>MCP-роутер (rmcp) + embed статики<br/>(static-serve, флаг embed-static);<br/>модули по доменам: documents · chat · mcp · views"]
        Runner["<b>crates/runner</b><br/>супервизор процессов; writer stdin;<br/>каузальный наблюдатель delivered;<br/>прослойка CLI (ADR-0009); брокер комплектов"]
        DB["<b>crates/db</b><br/>прослойка доступа ADR-0005 (CAS, retry);<br/>все query-макросы sqlx; migrations/"]
        Core["<b>crates/core</b><br/>типы, перечисления-истина, ошибки;<br/>без tokio/axum; sqlx — optional feature"]
    end

    FakeExec["<b>crates/fake-executor</b><br/>тестовый симулятор:<br/>сырые JSONL-фикстуры stream-json"]
    Contract["<b>tests/contract</b><br/>контрактные тесты S3–S5"]
    PG[("Postgres")]
    Cont["Контейнеры задач<br/>(claude -p)"]

    Compose -->|"hef serve / hef migrate"| Hef
    Hef --> API
    API --> Runner
    Runner --> DB
    API --> DB
    DB --> Core
    Runner --> Core
    API --> Core
    DB -->|"SQL (sqlx)"| PG
    Runner -->|"spawn/stop, stdin/stdout"| Cont
    FakeExec --> Core
    Contract -->|"запускает вместо CLI"| FakeExec
    Contract -->|"тестирует прослойку"| Runner
```

Заземлено в ADR-0014 (граф, границы крейтов, модульность `api`) и ADR-0005/0007/0009 (содержимое `db`/`runner`). CI-сторож чистоты `core` (без tokio/axum/sqlx в дефолтном графе) — часть конструкции, на диаграмме не показан. Фронт (`web/`) на этом уровне — источник статики для embed, не компонент бинаря.
