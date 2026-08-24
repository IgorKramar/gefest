#!/usr/bin/env bash
# Проверка самих сторожей: каждый обязан быть зелёным на чистом дереве и
# красным на внесённом нарушении.
#
# --- Зачем это существует ---------------------------------------------------
# Сторожа проверяют репозиторий, но их самих не проверяет ничто, а их отказ
# невидим по построению: сломанный сторож молча зеленеет, и это неотличимо
# от здорового состояния.
#
# Это не гипотеза. Ревью PR-1 нашло два сторожа, которые уже не могли
# сработать, хотя каждый был проверен вручную «от красного»:
#
#   1. guard-sqlx-step искал в ci.yml подстроку «prepare --check» — а она
#      появилась там же, в имени шага самого сторожа и в комментарии,
#      объясняющем его отсутствие. Ручная проверка прошла раньше, чем был
#      создан ci.yml, и перестала быть верной ровно в тот момент.
#   2. guard-core-graph звал cargo tree с --no-default-features и потому
#      смотрел не на дефолтный граф, а на граф с отключёнными дефолтами.
#
# Ручная проверка — снимок в момент написания; она не переживает изменения
# файлов вокруг. Этот скрипт превращает её в повторяемую.
#
# Намеренно red/green-смоук, а не набор тестов: он ловит единственный отказ,
# который иначе невидим — сторожа, переставшего быть способным покраснеть.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
REPO_ROOT="$PWD"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0

# Копия дерева без артефактов сборки и чужого кода.
copy_tree() {
    local dest="$1"
    mkdir -p "$dest"
    tar -C "$REPO_ROOT" \
        --exclude=./target \
        --exclude=./.git \
        --exclude=./reference \
        -cf - . 2>/dev/null | tar -C "$dest" -xf -
}

# expect_green <имя> <каталог> <сторож>
expect_green() {
    local name="$1" dir="$2" guard="$3"
    if (cd "$dir" && "./scripts/$guard" >/dev/null 2>&1); then
        echo "  OK   $name — зелёный на чистом дереве"
    else
        echo "  ПРОВАЛ $name — красный на ЧИСТОМ дереве (ложное срабатывание)" >&2
        failures=1
    fi
}

# expect_red <имя> <каталог> <сторож>
expect_red() {
    local name="$1" dir="$2" guard="$3"
    if (cd "$dir" && "./scripts/$guard" >/dev/null 2>&1); then
        echo "  ПРОВАЛ $name — ЗЕЛЁНЫЙ при внесённом нарушении" >&2
        echo "         Сторож не способен покраснеть: он больше ничего не охраняет." >&2
        failures=1
    else
        echo "  OK   $name — краснеет на нарушении"
    fi
}

echo "guard-selftest: проверяю сторожей от красного и от зелёного."
echo

# --- guard:toolchain-pin ---------------------------------------------------
echo "guard:toolchain-pin"
T="$WORK/pin"; copy_tree "$T"
expect_green "пин согласован" "$T" "guard-toolchain-pin.sh"
sed -i 's/^channel = ".*"/channel = "1.0.0"/' "$T/rust-toolchain.toml"
expect_red "версии разведены" "$T" "guard-toolchain-pin.sh"
echo

# --- guard:sqlx-step -------------------------------------------------------
echo "guard:sqlx-step"
S="$WORK/sqlx"; copy_tree "$S"
expect_green "макросов нет" "$S" "guard-sqlx-step.sh"
# Нарушение: настоящий макрос запроса при отсутствии шага в CI.
printf '\npub fn probe() { let _ = sqlx::query!("SELECT 1"); }\n' >> "$S/crates/db/src/lib.rs"
expect_red "есть query!, шага в CI нет" "$S" "guard-sqlx-step.sh"
# И обратно: с настоящим шагом сторож обязан снова позеленеть, иначе он
# запрещает то, ради чего заведён.
printf '\n      - name: sqlx\n        run: mise run sqlx:check\n' >> "$S/.github/workflows/ci.yml"
expect_green "есть query! и настоящий шаг" "$S" "guard-sqlx-step.sh"
echo

# --- guard:core-graph ------------------------------------------------------
echo "guard:core-graph"
C="$WORK/core"; copy_tree "$C"
expect_green "граф чист" "$C" "guard-core-graph.sh"
# Нарушение через ДЕФОЛТНУЮ фичу — случай, который сторож с
# --no-default-features не видел.
python3 - "$C/crates/core/Cargo.toml" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace(
    'sqlx = { workspace = true, optional = true }',
    'sqlx = { workspace = true, optional = true }\ntokio = { workspace = true, optional = true }',
)
s = s.replace('default = []', 'default = ["rt"]\nrt = ["dep:tokio"]')
open(p, 'w').write(s)
PY
expect_red "зависимость через дефолтную фичу" "$C" "guard-core-graph.sh"
echo

# --- Секретные паттерны .dockerignore --------------------------------------
# .dockerignore использует правила Go filepath.Match: `*` НЕ пересекает `/`,
# поэтому `*.key` ловит только корень контекста. .gitignore тот же паттерн
# применяет на любой глубине — файлы выглядят одинаково, ведут себя
# противоположно. Проверено сборкой: без `**/` в образ уезжали
# web/.env.local, infra/pgcrypto.key, infra/secrets/pool.txt и
# crates/db/local.pem.
#
# Проверка офлайновая: docker для неё не нужен.
echo "секретные паттерны .dockerignore"
secret_ok=1
for pat in '.env\*' '\*.pem' '\*.key' '\*.p12' '\*.age' 'secrets/'; do
    plain=${pat//\\/}
    if grep -qE "^\*\*/${pat}$" .dockerignore; then
        echo "  OK   **/$plain ловится на любой глубине"
    else
        echo "  ПРОВАЛ $plain объявлен без префикса **/ — вложенные пути уедут в образ" >&2
        secret_ok=0
    fi
done
[ "$secret_ok" -eq 0 ] && failures=1
echo

# --- Сверка списков проверок -----------------------------------------------
# Набор проверок описан дважды: шагами в ci.yml и в [tasks.ci] mise.toml.
# Расхождение молчаливо в опасную сторону: новый сторож, попавший только в
# mise.toml, проходит локально и никогда не запускается в CI.
echo "сверка списков проверок"
missing=0
for task in $(grep -oP '^\[tasks\."\Kguard:[^"]+' mise.toml); do
    if grep -q "mise run $task" .github/workflows/ci.yml; then
        echo "  OK   $task вызывается в CI"
    else
        echo "  ПРОВАЛ $task объявлен в mise.toml, но не вызывается в ci.yml" >&2
        missing=1
    fi
done
[ "$missing" -ne 0 ] && failures=1
echo

if [ "$failures" -ne 0 ]; then
    echo "guard-selftest: ЕСТЬ ПРОВАЛЫ — сторожа не выполняют свою работу." >&2
    exit 1
fi

echo "guard-selftest: все сторожа способны и покраснеть, и позеленеть."
