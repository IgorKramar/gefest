# Research digest: стек Гефеста (D-1) — Rust-экосистема и фронтенд, август 2026

Дайджест агента-исследователя, 2026-08-20 (light-цикл; структура — по шаблону research).

## Question

Актуальность axum/tokio/sqlx и альтернатив; MCP SDK на Rust; pgvector+sqlx; idle-RAM Rust vs Go vs Python; зрелость Bun как фронтенд-тулчейна; современный набор для React/TS SPA-панели с SSE.

## Headline finding

Стек axum 0.8.x + tokio + sqlx 0.9 + rmcp 3.x + pgvector-crate — зрелый мейнстрим 2026, всё официальное и живое. Для фронтенда безопасный выбор — Vite 8 (стабилен с марта 2026, Rolldown внутри) + TanStack Router/Query; Bun хорош как рантайм для install/test/dev, но как единственный бандлер для сложного React-SPA пока уступает Vite.

## Detailed findings

1. **axum/tokio/sqlx**: axum 0.8 (янв 2025, сейчас 0.8.9+; SSE и WebSocket встроенные; синтаксис путей `/{param}`); sqlx 0.9.0 — свежий мажор (21 мая 2026). Консенсус 2026 для нового проекта — axum (tower/hyper-экосистема); actix-web жив, но выбирают реже; poem — ниша. Супервизия subprocess: `tokio::process::Command` + построчное чтение stdout — стандартный приём.
2. **MCP SDK на Rust — официальный и зрелый**: `rmcp` (modelcontextprotocol/rust-sdk), **3.1.4 от 20 августа 2026**, ~21 млн загрузок; транспорты stdio/SSE/streamable HTTP, макросы `#[tool]`, schemars. Вопрос закрыт.
3. **pgvector**: официальный крейт pgvector-rust с фичей `sqlx` — гладкий путь (bind/try_get `pgvector::Vector`, halfvec). Не подтверждена совместимость именно с sqlx 0.9 — проверить при `cargo add`; фолбэк sqlx 0.8.
4. **Idle RAM (порядки, из блогов/опыта, не строгих бенчей)**: маленький axum-сервис в простое ~5–30 МБ RSS; Go типично в 2–4 раза больше; Python (uvicorn) 60–150+ МБ на воркер. Порядок Rust < Go < Python надёжен; конкретные мегабайты — нет; для биллинга сделать свой замер на прототипе.
5. **Bun (август 2026)**: официально линия **1.3.x** (1.3.14, май 2026); «Bun 2.0» из сторонних блогов — фейк/AI-слоп, сверяться только с bun.sh. Факт: **Bun куплен Anthropic (декабрь 2025), питает Claude Code**. `bun install`/`bun test` — зрелые; бандлер — рабочий для 80%, но для React-SPA обзоры советуют Vite. Прод-паттерн 2026: Bun как package manager + test runner + dev-скрипты, сборка Vite («Vite на Bun» — распространено).
6. **Фронтенд-набор**: **Vite 8 стабилен с 12 марта 2026** (Rolldown/Oxc внутри; Vite 7 — прошлый мажор). Консенсус для SPA без SSR: Vite 8 + React 19 + TS + TanStack Router + TanStack Query + Tailwind CSS 4. TanStack Start/RSC не нужны (бэкенд на Rust). SSE: нативный `EventSource` + инвалидация TanStack Query.

## Caveats and unknowns

Совместимость pgvector-крейта с sqlx 0.9 — проверить перед фиксацией; цифры idle-RAM — не бенчмарки, свой замер на прототипе (полдня); вокруг Bun и Rust-vs-Go много SEO/AI-шума — доверять первоисточникам.

## Implications for the design phase

Оба возражения против Rust сняты research-ом: MCP-SDK официальный и зрелый (rmcp 3.x), pgvector гладкий; экономика C-С1 подтверждает порядок Rust < Go < Python по idle-RAM. Bun — как toolchain (install/test/dev), сборка Vite 8; прод-рантайма для фронта нет — статика из axum.

## Sources

1. https://tokio.rs/blog/2025-01-01-announcing-axum-0-8-0 (янв 2025) · 2. https://github.com/tokio-rs/axum/releases · 3. https://devstarsj.github.io/2026/03/01/rust-async-tokio-axum-production-2026/ (март 2026) · 4. https://medium.com/@abhinav.dobhal/actix-web-vs-e1e019714542 (2026, среднее качество) · 5. https://github.com/modelcontextprotocol/rust-sdk + crates.io rmcp 3.1.4 (2026-08-20) · 6. https://docs.rs/rmcp · 7. https://github.com/pgvector/pgvector-rust + https://docs.rs/pgvector · 8. https://crates.io/crates/sqlx (0.9.0, 2026-05-21) · 9. https://www.danilchenko.dev/posts/rust-vs-go/ (2026) · 10. https://markaicode.com/rust-vs-go-performance-benchmarks-microservices-2025/ · 11. https://bun.sh/blog (1.3.14, май 2026) · 12. https://last9.io/blog/getting-started-with-bun-js/ (2026) · 13. https://medium.com/@oliveryasuna.main/the-case-for-bun-in-2026-where-it-works-and-where-it-doesnt-1cf61a55d1c9 · 14. https://vite.dev/blog (Vite 8, март 2026) · 15. https://www.patterns.dev/react/react-2026/ · 16. https://makerkit.dev/blog/tutorials/tanstack-start-vs-nextjs (вендор)
