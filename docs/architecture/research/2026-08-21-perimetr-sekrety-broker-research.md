# Research digest: периметр, секреты и брокер (D-7)

- Дата: 2026-08-21 · Два потока: (1) российские облачные провайдеры + Anthropic-egress; (2) Tailscale/Headscale в РФ + mTLS/passkeys + axum-сторона. Полные отчёты — в истории цикла; здесь выжимка с источниками.

## 1. Провайдеры (для отдельного хоста Гефеста)

| Провайдер | ~2 vCPU/4 ГБ/50 ГБ | Биллинг | Заметки |
|---|---|---|---|
| Yandex Cloud | ~1500–2500 ₽/мес (меньше с долей vCPU 20–50%) | Посекундно; **остановленная VM не тарифицирует vCPU/RAM** (docs 07.2026) | Снапшоты ~3,7 ₽/ГБ·мес; Object Storage ~2 ₽/ГБ·мес — pg_dump вне хоста в том же аккаунте |
| Timeweb Cloud | ~1062–1700 ₽/мес фикс | Почасовой фикс; останов не освобождает | Самый простой; S3 от 1 ₽/ГБ; можно жить без публичного IPv4 (вход только tailnet) |
| Serverspace | от 249 ₽, поминутно | Pay-as-you-go | **ДЦ в РФ и за рубежом в одном аккаунте** — удобно для split-egress |
| VK Cloud / Selectel / beget / Cloud.ru | порядок тот же | поминутно/почасово; детали не подтверждены | Cloud.ru free tier (2 vCPU@10%/4 ГБ/30 ГБ) — стенд, не прод |

**Рекомендация research: Yandex Cloud** (единственный документально подтверждённый «останов = не платим» — прямое попадание в C-С1) или Timeweb (если нагрузка 24/7 и важен предсказуемый фикс).

## 2. Anthropic-egress — критическая находка

РФ **нет** в supported countries Anthropic; проверяются IP и страна биллинга; 01.2026 — закрыт OAuth вне интерфейсов Claude; 04.2026 — верификация Persona; весна 2026 — массовые баны российских аккаунтов. **Исполнители на VM с российским IP не заработают ни у одного провайдера** — проблема не в провайдерах. Практика: **split-egress** — данные/VM в РФ (152-ФЗ), исходящий к api.anthropic.com через зарубежную точку (exit node в tailnet, policy-routing доменов Anthropic). По ToS Anthropic использование из неподдерживаемого региона — нарушение; риск бана сохраняется и при зарубежном egress; «работает без банов» пишут аффилированные источники. Решение по egress — до выбора хостинга (Q8 владельцу).

## 3. Tailscale/Headscale

- Официальный Tailscale SaaS с российских IP — HTTP 451 с 10.2024 (координатор, админка, логин). На SaaS не закладываться.
- **Headscale 0.29.x** (лето 2026): ACL-синтаксис Tailscale, grants; официальные клиенты iOS/Android подключаются по custom server URL (iOS ≥ 1.38.1); embedded DERP есть — свой DERP обязателен (РКН эпизодически глушит голый WireGuard, DERP внутри — смягчение). Трудозатраты: выходные на настройку, минуты в месяц; читать changelog перед мажорными апгрейдами (слом policy v1→v2 в 0.26 — прецедент).
- **ACL пер-нодовые**: контейнеры на хосте — не ноды, ACL их не видит. Изоляция owner-поверхности от исполнителей делается **на хосте**: owner-listener биндится только на Tailscale-IP, MCP-listener — только на IP docker-моста/unix socket; nftables запрет bridge → `tailscale0`; контейнеры не в host netns.
- Identity headers (`Tailscale-User-Login` через serve) в нашей топологии **небезопасны**: backend на localhost доступен контейнерам — заголовки подделываемы (инцидент-прецедент 2026). tsnet — Go-only.

## 4. Auth владельца: mTLS против passkeys

- **mTLS на мобильных болен**: iOS — p12 через профиль, работает только Safari (Chrome/Firefox/WKWebView не отправляют клиентский сертификат), PWA нестабильно; Android — только Chrome; ротация целиком ручная на каждом устройстве ежегодно; история багов «Safari переспрашивает сертификат».
- **Passkeys (WebAuthn)**: enrolment — один тап, любой браузер и PWA на обоих платформах, ротации нет, фишинг-устойчивы; Rust-сторона зрелая — `webauthn-rs` (ядро Kanidm). Поверх tailnet фактическая стойкость сопоставима с mTLS; mTLS формально строже (аутентифицирует соединение), passkeys на порядок дешевле в эксплуатации.
- axum/rustls: peer-сертификаты из коробки не экспонируются (issues #677/#2697) — нужен `axum-server-mtls` или свой Acceptor; verifier — свойство листенера целиком. Два независимых листенера (owner/MCP) в одном tokio — тривиально; это же и механизм изоляции.
- Общий риск обоих вариантов: падение tailnet (блокировка WireGuard) = потеря входа → аварийный путь (SSH к VM) обязателен.

## Caveats

Цены — порядки, сверять калькуляторами; даты патч-релизов headscale сверить по github releases; доступность приложений Tailscale в российских сторах проверить с устройства; поведение client certs в iOS-PWA на текущих iOS не подтверждено свежими источниками; политика Anthropic ужесточалась трижды за 2026 — выводы стареют за месяцы.

## Sources

Полные списки (40 позиций с датами) — в отчётах research-агентов; ключевые: docs Yandex Compute (тарификация, 07.2026); anthropic.com/supported-countries; 3dnews/Habr 2026 (баны, OAuth, Persona); github tailscale#13648 (451, 10.2024); github.com/juanfont/headscale/releases (0.29.x); Tailscale docs Serve/identity; docs.rs/axum-server-mtls; tokio-rs/axum#677/#2697; FusionAuth WebAuthn docs.

*Terminology pass: проза русская; идентификаторы (Tailscale, Headscale, DERP, tsnet, split-egress, exit node, p12, WebAuthn, `webauthn-rs`, `axum-server-mtls`, nftables, `tailscale0`, pg_dump, S3, ToS, Persona) без перевода.*
