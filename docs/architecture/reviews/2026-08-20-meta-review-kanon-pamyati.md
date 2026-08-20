# Meta-review: roast D-8 (kanon-pamyati) + фазовые документы цикла

**Target**: `docs/architecture/reviews/2026-08-20-roast-kanon-pamyati/` + фазовые документы цикла в `docs/architecture/research/`
**Date**: 2026-08-20
**Plugin version**: architect 1.1.0
**Статус применения**: M-1…M-5 применены в тот же день (правки каталога + раздел Reviews в decision ред. 2); M-6 — принять к сведению для будущих research-документов; M-7 — дефект спецификации плагина, не артефактов.

## Findings (кратко)

- **M-1 (high, identifier preservation)**: cross-cutting-идентификаторы `К-1…К-8` (кириллица) вместо предписанных `CC-N`. → Переименованы в CC-1…CC-8.
- **M-2 (medium, template conformance)**: Headline findings — кластеры вместо «одна строка на роль». → Переформатированы в пять строк по ролям; кластеры остались в Cross-cutting concerns.
- **M-3 (medium, template conformance)**: находки трёх ролей (03/04/05) — буллетами вместо `### X-N:`-подзаголовков. → Развёрнуты в подзаголовки.
- **M-4 (medium, lifecycle integrity)**: review-trail не добавлен в decision («ожидает roast», хотя roast выполнен). → Добавлен раздел `## Reviews`, статус обновлён.
- **M-5 (low)**: заголовок summary и регистр таблицы severity. → Исправлены (`# Roast: …`, High/Medium/Low, имена ролей с заглавной).
- **M-6 (medium)**: research-документ цикла не следует output-структуре `commands/research.md` (свои секции R1–R4; `## Sources` есть). → Оставлен как исторический; следующие research — по шаблону.
- **M-7 (low, spec-level)**: внутренний конфликт спецификации плагина по ID-схемам (`agents/devil-advocate.md` говорит A-1, `commands/roast.md` — B-1). Артефакты следуют roast.md консистентно. Вопрос к roadmap плагина.

## What conforms

Каталог: место/имя/состав по шаблону; verbatim-заголовки summary; ID-схемы ролей латиницей без пропусков; severity-счёты сходятся во всех ячейках (13/20/4 = 38); кросс-ссылки разрешаются (включая GF-4 и легенду decision); Recommended path — verbatim-вариант; language pass во всех шести файлах; роль-специфичные заголовки verbatim. Фазовые документы: discovery — 7 секций + Section 7 verbatim; design — 4 альтернативы со статус-кво, матрица, not-considered; decision — все 7 блоков.
