#!/usr/bin/env bash
# Растяжка под отложенный сторож `sqlx prepare --check`.
#
# В PR-1 сторожа синхронности .sqlx нет намеренно: сторожить нечего (ни
# одного query!, ни .sqlx, ни миграций), а честного пути до зелёного без
# живого Postgres не существует.
#
# Но отложенный сторож не должен держаться на памяти автора следующего PR.
# Эта проверка красная ровно тогда, когда появился первый макрос запроса, а
# CI-шага prepare --check всё ещё нет. Ресурсов не требует: только чтение
# файлов.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

WORKFLOW=".github/workflows/ci.yml"

# Комментарии не считаются: крейт hef-db документирует собственную границу
# словами «макросы запросов (query!, query_as!)», и наивный поиск принимает
# документацию за код. Отбрасываем строки, начинающиеся с //, //! или ///.
macros_found=$(
    grep -rnE '\bquery(_as|_file|_file_as|_scalar)?!' crates/ --include='*.rs' 2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
        | cut -d: -f1 \
        | sort -u \
        || true
)

if [ -z "$macros_found" ]; then
    echo "guard:sqlx-step — макросов запросов нет, сторож prepare --check пока не нужен."
    exit 0
fi

if [ -f "$WORKFLOW" ] && grep -q 'prepare --check' "$WORKFLOW"; then
    echo "guard:sqlx-step — макросы запросов есть, шаг prepare --check на месте."
    exit 0
fi

echo "guard:sqlx-step — в crates/ появились макросы запросов:" >&2
echo "$macros_found" >&2
echo >&2
echo "Но в $WORKFLOW нет шага 'prepare --check'." >&2
echo "Синхронность .sqlx с реальными запросами не сторожится ничем." >&2
echo >&2
echo "Что делать: добавить в CI шаг с service-контейнером Postgres и" >&2
echo "'mise run sqlx:check'. Подробности — crates/db/README.md." >&2
exit 1
