# Research-дайджест: канон памяти (D-8) — EverOS и текущие слои

- Дата: 2026-08-20
- Фаза: Research (deep-цикл D-8), после discovery раунда 2
- Метод: (1) веб-разведка EverOS; (2) разбор исходников `reference/everos` (v1.2.3, 657 py, ~114k LOC); (3) собственная проверка ключевого утверждения исполнением

## R1. EverOS: что это на самом деле

- Не «слой», а **полноценный сервис**: FastAPI + SQLite (SQLModel/Alembic) + LanceDB + APScheduler + TUI. Markdown — источник истины («снёс индексы — пересобрал из md»), atomic write (temp + `os.replace`), entry-id `<prefix>_<YYYYMMDD>_<NNNNNNNN>`, HTML-comment маркеры записей. Лицензия Apache 2.0 (+ карвэ-аут: одна тестовая фикстура CC BY-NC).
- **Алгоритмы вынесены** в отдельные пакеты `everalgo-*` (пин `==0.4.0` при актуальных 0.7.x — рассинхрон).
- **GitHub — экспортное зеркало закрытого GitLab** («no shared commit history»; внешние PR «curated») — форк без пути вливания наверх.
- Релизы: 12 за 2 месяца; слова «BREAKING» нет, но ломающие изменения едут в патчах (смена PK в 1.2.3). Тесты — 2183 функции, CI с контролем слоёв — инженерно сильно.

## R2. Три блокера для нашего кейса

1. **Русский поиск мёртв в бесплатном режиме — ПОДТВЕРЖДЕНО ИСПОЛНЕНИЕМ** (2026-08-20, jieba 0.42.1, python 3.14): `cut_for_search('память команды агентов')` → посимвольно → после фильтра `min_token_length=2` → `[]`. Кириллица не входит в `re_han_default`; BM25-колонка пуста, keyword-запрос молча возвращает пустоту — а keyword — единственный метод бесплатного Tier 1. Векторная нога (Qwen3-Embedding, мультиязычная) работала бы, но требует платного/локального embedding-провайдера; стеммер — английский Snowball; тестов на кириллицу — ноль. Починка = форк токенизатора + полный rebuild + отсутствие апстрима.
2. **Стек не наш и не станет нашим**: SQLite+LanceDB — архитектура, не конфиг (Postgres невозможен без переписывания `infra/persistence` и каскада); один процесс на memory-root (`Cross-process safety is out of scope… enterprise edition layers a distributed coordinator»); поиск строго XOR user/agent — общей командной памяти нет.
3. **Интеграции с Claude Code нет**: официальный плагин — легаси-обёртка облачного EverMem (`EVERMEM_API_KEY`, старый `/api/v1`, на self-hosted не перенаправляется); MCP-сервера в репо нет; CLI без записи/чтения (hot-path — только HTTP). Обвязку писать самим в любом случае.

Дополнительно: `/search` — eventual consistency («под нагрузкой до 10–15 с») — опасно для цикла «агент записал → следующий сразу ищет»; фоновая OME — 3–4 LLM-вызова на закрытый memcell (на бесплатном OpenRouter упрётся в rate limits).

## R3. Что у EverOS стоит забрать (идеи, бесплатно)

- **Спецификация хранения** (`docs/storage_layout.md`): frontmatter-шасси, entry-id, поэнтрийная переиндексация по `content_sha256`, durable-очередь изменений (`md_change_state`) — у нас это таблица в Postgres.
- **Трёхстадийный агентский цикл** recall → capture → flush с fail-open и батчингом (`examples/dsh/` — лучший образец обвязки в репо).
- **Контракт API**: `sender_id`+`role` для атрибуции, `defer_extraction` для дешёвого капчура, честное предупреждение об eventual consistency.
- **Конфиг фоновых LLM-процессов** (`default_ome.toml`): каждая стратегия выключается строкой, опечатка в ключе = StartupValidationError (не молчаливый пропуск); самые дорогие стратегии выключены по умолчанию; OpenRouter — родной дефолт.
- Скоупы памяти `user/agent/app/project/session` и разделение поверхностей (profile/episodes/cases/skills) — словарь для нашей схемы.

## R4. Подтверждения по текущим слоям (из инвентаризации discovery)

- Русский FTS в Postgres у нас уже работает (agent-dashboard `documents`, `to_tsvector('russian')`) — проверено эксплуатацией.
- Прототип «канон → инжекция» (30-resources + SessionStart-хук) работает, предел — токены; трёхслойная модель Р-1 это лечит.
- Механика «выгрузки вниз» для памяти ролей имеет готовый образец: yao genfile-подход (docs/06 §1.6), включая правило «MEMORY.md не перезаписывать».

## Выводы для Design

1. **EverOS как зависимость — вычеркнут** тремя независимыми блокерами (каждого достаточно); владелец ставил условие «готов, если того стоит» — не стоит. Остаётся донором идей (R3).
2. Развилка Design сужается до: **канон в Postgres** (расширение проверенной documents-модели) против **канон в md-файлах репо + индекс** (EverOS-стиль своими руками) против статус-кво.
3. Русский поиск — решённая задача только в Postgres-варианте (эксплуатационное доказательство); в md-варианте FTS всё равно строится в Postgres/SQLite → двойное хранилище.
4. Ограничение LLM-бюджета выполнимо в обоих вариантах: фоновая консолидация — бесплатный OpenRouter, по образцу ome.toml (выключаемо, с явной ценой на запись).

## Sources

1. Веб-дайджест EverOS (агент-исследователь, 2026-08-20): README, docs/overview, docs/configuration, releases, claude-code-plugin README, issues #378/#382/#396/#397/#402/#413, MarkTechPost 2026-06-29 — https://github.com/EverMind-AI/EverOS
2. Разбор исходников: `reference/everos` v1.2.3 (клон 2026-08-20) — pyproject.toml, docs/{storage_layout,api,cli,reflection,knowledge,github-sync}.md, src/everos/{component/tokenizer,config,infra/ome,service,memory/search}, use-cases/claude-code-plugin, examples/dsh, tests (2183 функции), CHANGELOG, LICENSE/NOTICE
3. Проверка исполнением (оркестратор, 2026-08-20): jieba 0.42.1 на кириллице — посимвольный вывод, пустой результат после фильтра `min_token_length=2`
4. Инвентаризация слоёв памяти — discovery `2026-08-20-kanon-pamyati.md` §2
