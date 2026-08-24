#!/usr/bin/env bash
# Сторож согласованности пина Rust между mise.toml и rust-toolchain.toml.
#
# Файлы не конфликтуют, но и не эквивалентны: mise экспортирует
# RUSTUP_TOOLCHAIN, который в порядке приоритетов rustup стоит выше файла.
# Внутри `mise run` (и в CI) побеждает пин mise; редактор, rust-analyzer и
# голый cargo читают rust-toolchain.toml.
#
# Опасность не в конфликте, а в тихом расхождении версий между CI и рабочим
# местом. Проверка офлайновая: сравнение двух строк.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

mise_pin=$(grep -oP '^\s*rust\s*=\s*"\K[^"]+' mise.toml || true)
toolchain_pin=$(grep -oP '^\s*channel\s*=\s*"\K[^"]+' rust-toolchain.toml || true)

if [ -z "$mise_pin" ]; then
    echo "guard:toolchain-pin — в mise.toml не найден пин rust в [tools]." >&2
    exit 1
fi

if [ -z "$toolchain_pin" ]; then
    echo "guard:toolchain-pin — в rust-toolchain.toml не найден channel." >&2
    exit 1
fi

if [ "$mise_pin" != "$toolchain_pin" ]; then
    echo "guard:toolchain-pin — версии Rust разошлись:" >&2
    echo "  mise.toml           rust    = $mise_pin" >&2
    echo "  rust-toolchain.toml channel = $toolchain_pin" >&2
    echo >&2
    echo "CI собирает пином mise, редактор и голый cargo — пином файла." >&2
    echo "Приведите обе строки к одной версии." >&2
    exit 1
fi

echo "guard:toolchain-pin — пин согласован: $mise_pin."
