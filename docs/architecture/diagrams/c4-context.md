# C4 (context): Гефест в мире

L1: система и её окружение. Внутренности — `c4-container-orkestrator.md`; хосты и сеть — `deployment-perimetr.md`.

```mermaid
graph TB
    Owner["<b>Владелец</b><br/>(Игорь: ноутбук, телефон)"]

    Gefest["<b>Гефест</b><br/>Оркестратор команды Claude Code-агентов:<br/>задачи, доставка указаний, сессии, чат,<br/>канон памяти и документов, брокер ресурсов"]

    Anthropic["<b>API Anthropic</b><br/>(подписка Max; LLM исполнителей)"]
    GitHub["<b>GitHub</b><br/>(репо Гефеста, Actions-CI, GHCR;<br/>+ рабочие репо задач)"]
    GitLab["<b>GitLab</b><br/>(рабочие репо задач)"]
    Alerts["<b>Каналы алертов</b><br/>Telegram · ntfy · почта"]
    HB["<b>Внешний heartbeat</b><br/>(healthchecks-класс)"]
    S3["<b>S3 РФ-провайдера</b><br/>(бэкап вне хоста)"]

    Owner -->|"управляет через tailnet: панель (passkeys), команды, подтверждения"| Gefest
    Gefest -->|"LLM-запросы исполнителей (split-egress через EU)"| Anthropic
    Gefest -->|"push / MR агентов; детекторы сверяют статус с фактом мержа/CI"| GitHub
    Gefest -->|"push / MR агентов; детекторы"| GitLab
    Gefest -->|"алерты: только факт + ссылка"| Alerts
    Gefest -->|"ping каждые ≤ 5 мин"| HB
    Gefest -->|"pg_dump ежесуточно (шифрован)"| S3
    Alerts -->|"догоняют вне панели"| Owner

    style Gefest fill:#1168bd,stroke:#0b4884,color:#fff
    style Owner fill:#08427b,stroke:#052e56,color:#fff
    style Anthropic fill:#999,stroke:#666,color:#fff
    style GitHub fill:#999,stroke:#666,color:#fff
    style GitLab fill:#999,stroke:#666,color:#fff
    style Alerts fill:#999,stroke:#666,color:#fff
    style HB fill:#999,stroke:#666,color:#fff
    style S3 fill:#999,stroke:#666,color:#fff
```

Заземлено в ARCHITECTURE.md и ADR-0007/0010/0011/0012; GitHub несёт три роли одного вендора (репо+CI+GHCR — ADR-0012/0014). Исполнители — внутри системы (контейнеры Гефеста), поэтому на L1 не показаны.
