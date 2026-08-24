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
# Сканируем корень репозитория, а не только crates/: контрактные тесты по
# ADR-0014 лежат в tests/contract/, вне crates/, и их query! иначе невидимы.
# reference/ и target/ исключены — это чужой код и артефакты сборки.
macros_found=$(
    grep -rnE '\bquery(_as|_file|_file_as|_scalar)?!' . \
        --include='*.rs' \
        --exclude-dir=target \
        --exclude-dir=reference \
        --exclude-dir=.git \
        2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
        | cut -d: -f1 \
        | sort -u \
        || true
)

if [ -z "$macros_found" ]; then
    echo "guard:sqlx-step — макросов запросов нет, сторож prepare --check пока не нужен."
    exit 0
fi

# Ищем ИСПОЛНЯЕМУЮ команду, а не фразу. Наивный `grep -q 'prepare --check'`
# обезвреживает сторожа мгновенно: эта фраза уже встречается в ci.yml четыре
# раза — в имени шага самого сторожа и в комментарии, объясняющем, почему
# шага пока нет. Сторож был бы зелёным всегда.
#
# `^[^#]*` отбрасывает строки-комментарии YAML, чтобы будущее упоминание
# команды в комментарии не обезвредило сторожа повторно.
if [ -f "$WORKFLOW" ] && grep -qE '^[^#]*(mise run sqlx:check|sqlx prepare --check)' "$WORKFLOW"; then
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
