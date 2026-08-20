# Meta-review: roast-каталог shema-dannyh + фазовые документы цикла D-2

**Target**: `docs/architecture/reviews/2026-08-20-roast-shema-dannyh/` + `research/2026-08-20-shema-dannyh*`
**Date**: 2026-08-20 · **Plugin version**: architect 1.1.0
**Статус применения**: M-1, M-2, M-4 применены (коммит после roast); M-3 и M-6 — закрыты decision ред. 2 (отдельный блок Migration path, раздел Reviews); M-5 — What survived оставлен как аддитив.

## Findings (кратко)

- **M-1 (medium)**: pragmatist слил `## What's understated in the proposal` и `## What's missing entirely` в один невербатимный заголовок. → Разбит.
- **M-2 (medium)**: discovery — 6 секций вместо 7 (QA/constraints растворены в §3–4, «Инвентарь» добавочен). → Строка-легенда об адаптации добавлена.
- **M-3 (low)**: decision без отдельного блока Migration path. → Ред. 2 содержит §6 Migration path.
- **M-4 (low)**: строка «Итого» против правила «Don't sum»; колонка «всего». → Строка убрана (счёт вынесен строкой с оговоркой), колонка переименована в Total.
- **M-5 (low)**: `## What survived` вне шаблона. → Оставлена как полезный аддитив.
- **M-6 (low)**: review-trail не дописан в decision, статус устарел. → Ред. 2: раздел Reviews, статус обновлён.

## Пересчёт severity

Полная сходимость summary ↔ файлы ролей: B 6/2/0, H 2/4/1, J 2/6/1, C 2/4/1, F 1/5/2; суммарно 13/21/5 = 39.

## What conforms

Каталог (место/имя/состав), verbatim-заголовки summary и ролей, ID-схемы (B/H/J/C/F, CC-N), кросс-ссылки (D-N, GF-N, ADR-N), Recommended path verbatim-формой, language pass во всех файлах; research — полное соответствие шаблону; design — 4 альтернативы/матрица/not-considered.
