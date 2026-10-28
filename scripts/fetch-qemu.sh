#!/usr/bin/env bash
# Достаёт QEMU (qemu-aarch64-softmmu.framework) и все его зависимости
# из официального UTM.ipa. В сборке UTM QEMU уже собран под iOS как
# динамическая библиотека с поддержкой TCG JIT (split-wx) — повторно
# собирать QEMU и ~20 библиотек под iOS не нужно.
#
# Использование: scripts/fetch-qemu.sh <каталог-назначения>
set -euo pipefail

UTM_VERSION="${UTM_VERSION:-v5.0.7}"
UTM_SHA256="${UTM_SHA256:-8ba0eb413be248acc4c1d8704ccfe5d32e7c77c0630a199e2bfdb8619aa2d1ec}"
DEST="${1:?укажите каталог назначения}"
ROOT_FRAMEWORK="qemu-aarch64-softmmu.framework"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Загрузка UTM.ipa $UTM_VERSION"
curl -fsSL --retry 3 -o "$WORK/UTM.ipa" "https://github.com/utmapp/UTM/releases/download/$UTM_VERSION/UTM.ipa"
if [ -n "$UTM_SHA256" ]; then
    echo "$UTM_SHA256  $WORK/UTM.ipa" | shasum -a 256 -c -
fi
unzip -q "$WORK/UTM.ipa" 'Payload/UTM.app/Frameworks/*' -d "$WORK"
SRC="$WORK/Payload/UTM.app/Frameworks"

# Список @rpath-зависимостей Mach-O (otool на macOS, llvm-objdump на Linux)
deps() {
    local bin="$1/$(basename "$1" .framework)"
    if command -v otool >/dev/null; then
        otool -L "$bin" | tail -n +2 | awk '{print $1}'
    else
        llvm-objdump --macho --dylibs-used "$bin" | tail -n +2 | awk '{print $1}'
    fi | grep '^@rpath/' | sed -e 's|^@rpath/||' -e 's|/.*||' | sort -u
}

seen=" "
queue="$ROOT_FRAMEWORK"
while [ -n "$queue" ]; do
    set -- $queue
    fw="$1"; shift; queue="$*"
    case "$seen" in *" $fw "*) continue ;; esac
    [ -d "$SRC/$fw" ] || { echo "нет $fw в UTM.ipa" >&2; exit 1; }
    seen="$seen$fw "
    for d in $(deps "$SRC/$fw"); do
        case "$seen" in *" $d "*) ;; *) queue="$queue $d" ;; esac
    done
done

mkdir -p "$DEST"
count=0
for fw in $seen; do
    rm -rf "$DEST/$fw"
    cp -R "$SRC/$fw" "$DEST/"
    count=$((count + 1))
done
echo "==> Скопировано $count фреймворков в $DEST:"
printf '    %s\n' $seen | sort
du -sh "$DEST"
