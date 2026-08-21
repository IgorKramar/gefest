# Research digest: документный слой (D-10)

- Дата: 2026-08-21 · Темы: (1) редактор с поведением Obsidian Live Preview для React; (2) dataview-класс запросов поверх Postgres. Выжимка; полный отчёт — в истории цикла.

## 1. Редактор: reveal-у-курсора живёт только в мире CodeMirror 6

WYSIWYG-фреймворки (Milkdown/ProseMirror v7.21.3 07.2026; MDXEditor/Lexical) прячут разметку насовсем — поведение «сырой markdown проявляется у курсора» им архитектурно недоступно; к тому же они держат свою модель документа и нормализуют markdown при round-trip («текст остаётся текстом» нарушается систематически). Сам Obsidian, SilverBullet и Joplin (Rich Markdown) — CodeMirror 6 + декорации.

| Кандидат | Суть | Вердикт |
|---|---|---|
| **Atomic Editor** (`@atomic-editor/editor`, MIT, Show HN 06.2026) | React-компонент на CM6: reveal у курсора — его суть; `[[wiki]]` с async-автодополнением; подсветка 20+ языков lazy; read-only режим; виртуализация | Лучшее совпадение с ТЗ; молодой (~132 звезды, bus factor ≈ 1) |
| codemirror-live-markdown (MIT) | То же поведение, framework-agnostic; +KaTeX, GFM-таблицы | Референс/запасной |
| Своя сборка CM6 | Ядро reveal — 1–2 недели; хвост (таблицы, embed, IME) — месяцы | Дороже готового молодого |
| HyperMD (CM5), ink-mde | Мертвы/заглохли | Не брать |

Mobile: CM6 в мобильном браузере работоспособен (Obsidian mobile, Joplin — CM6), шероховатости с виртуальной клавиатурой/автодополнением по касанию; read-only чтение — без проблем. Atomic Editor на телефоне и React 19 Strict Mode — проверить руками до коммита на него. План Б встроен: MIT-код небольшого объёма поверх стабильного CM6 — форк посилен одному.

## 2. Dataview: DQL не переносим, экосистема ушла к GUI-видам

Dataview заморожен (0.5.70 beta 04.2026, master без коммитов ~год, 600+ issues); Datacore — вечная бета, привязан к Obsidian API; standalone-DQL нет (подтверждено maintainer, discussion #1811). Сам Obsidian ушёл к **Bases** (ядро с 1.9): сохранённый GUI-вид = фильтр + сортировка + layout — тот же паттерн, что Notion database views. SilverBullet — Lua-запросы по индексу объектов (Lua-runtime ради одного владельца — оверкилл). MarkdownDB решает проблему «md-файлы → SQL», которой у нас нет: метаданные уже в Postgres.

**Рекомендация research:** DQL не тащить. Свой тонкий слой «сохранённых видов» (оценка — дни): `saved_views` = JSON-спека `{filters: tag/date/links-to/from, sort, columns, layout}`; один построитель SQL в axum (параметризованный, без сырого SQL от клиента); встраивание вида в заметку fenced-блоком ` ```view `; аварийный люк — сохранённые raw-SQL под read-only ролью, только владельцу (строго мощнее DQL). Риск — ползучий DSL: computed-поля не добавлять в спеку, это территория raw-SQL-люка.

## Caveats

Mobile-опыт Atomic Editor не проверен вживую; даты последних коммитов молодых проектов не зафиксированы точно; React 19-совместимость не декларирована — проверить Strict Mode.

## Sources

Ключевые: github.com/kenforthewin/atomic-editor (+Show HN 06.2026); github.com/blueberrycongee/codemirror-live-markdown; Milkdown releases v7.21.3 (07.2026); silverbullet.md/Architecture (+2.5 LIQ); joplinapp.org CM6/Rich Markdown; obsidian-dataview discussion #1811; obsidian.rocks и abdulkadersafi.com — Dataview vs Datacore vs Bases (2026); practicalpkm.com — миграция Dataview→Bases. Полный список (13 позиций) — в отчёте research-агента.

*Terminology pass: проза русская; идентификаторы (CodeMirror 6, `@atomic-editor/editor`, Live Preview, DQL, Bases, `saved_views`, fenced-блок, KaTeX, GFM, IME, round-trip) без перевода.*
