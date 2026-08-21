# Deployment: периметр Гефеста — два хоста, tailnet, split-egress (ADR-0010)

Что где запущено и как соединено. Логика приложения — `c4-container-orkestrator.md`.

```mermaid
graph TB
    subgraph OwnerDev["Устройства владельца (tailnet-ноды)"]
        Laptop["<b>Ноутбук</b><br/>Tailscale-клиент + браузер (passkey)"]
        Phone["<b>Телефон</b><br/>Tailscale-клиент + PWA (passkey)"]
    end

    subgraph EU["EU VPS (~€3–5/мес)"]
        HS["<b>Headscale 0.29.x</b><br/>координатор tailnet"]
        DERP1["<b>DERP-релей</b> (основной)"]
        Exit["<b>Exit node</b><br/>policy-routing: только домены Anthropic"]
    end

    subgraph RF["РФ-VM (Timeweb-класс, без публичного IPv4)"]
        Bin["<b>Гефест</b> (один бинарь)<br/>owner-листенер: Tailscale-IP · MCP: мост<br/>nftables: мост ↛ tailscale0"]
        PG[("<b>Postgres</b><br/>+ pgcrypto (ключ файлом 0600)")]
        Cont["<b>Контейнеры задач</b> (rootless podman)<br/>claude -p, эфемерные"]
        DERP2["<b>DERP-вторичка</b><br/>(embedded, связность внутри РФ)"]
    end

    Anthropic["api.anthropic.com<br/>(вне РФ-доступа)"]
    Git["GitHub / GitLab"]
    S3["S3 РФ-провайдера<br/>(бэкап pg_dump)"]

    Laptop -- "координация (HTTPS)" --> HS
    Phone -- "координация (HTTPS)" --> HS
    Bin -- "координация (HTTPS)" --> HS
    Laptop -- "WireGuard p2p / DERP-fallback" --> Bin
    Phone -- "WireGuard p2p / DERP-fallback" --> Bin
    Laptop -. "релей при глушении WG" .-> DERP2
    Cont -- "HTTPS к Anthropic → маршрут через tailnet" --> Exit
    Exit -- "HTTPS (европейский IP)" --> Anthropic
    Cont -- "git push (напрямую, без exit node)" --> Git
    Bin -- "pg_dump ежесуточно (шифрован)" --> S3
    Bin --- PG
    Bin --- Cont
```

Заземлено в ADR-0010; курсивных домыслов нет. Аварийный путь (SSH/консоль провайдера при падении tailnet) и алерт-каналы не показаны, чтобы не перегружать вид — они в ADR-0010. Падение EU VPS: существующие tailnet-связи живут (ключи у клиентов), теряются Anthropic-egress и приём новых нод — восстановление по снапшоту (GF-3/GF-6).
