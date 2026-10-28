#!/usr/bin/env bash
# Собирает гостевую систему JITerm: Alpine Linux aarch64 с python/vim/и т.д.
#
# Результат (в каталоге OUT, по умолчанию ./out):
#   vmlinuz-virt     ядро Alpine linux-virt
#   initramfs-virt   initramfs (virtio + ext4)
#   rootfs.qcow2     корневая ФС ext4 (виртуальный размер DISK_SIZE, сжатый qcow2)
#   guest.json       версии компонентов
#
# Требования (Linux x86_64 или aarch64): root, curl, tar, e2fsprogs (mkfs.ext4 -d),
# qemu-img, и qemu-user-static с binfmt_misc для aarch64, если хост не aarch64.
set -euo pipefail

ALPINE_VERSION="${ALPINE_VERSION:-3.24}"
ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
DISK_SIZE="${DISK_SIZE:-8G}"
OUT="$(realpath -m "${1:-out}")"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE_PACKAGES=(alpine-base alpine-keys busybox-openrc)
PACKAGES=(
    linux-virt mkinitfs
    bash bash-completion coreutils findutils grep sed gawk diffutils less ncurses ncurses-terminfo
    util-linux-misc procps-ng e2fsprogs e2fsprogs-extra shadow sudo tzdata ca-certificates
    python3 py3-pip py3-virtualenv
    vim nano tmux htop tree file jq
    git curl wget openssh-client rsync
    tar gzip xz zip unzip
    man-pages mandoc
)

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите от root (sudo $0)"
for tool in curl tar mkfs.ext4 qemu-img; do
    command -v "$tool" >/dev/null || die "не найден $tool"
done

HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" != "aarch64" ]; then
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        [ -e /proc/sys/fs/binfmt_misc/register ] || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc || true
        for conf in /usr/lib/binfmt.d/qemu-aarch64.conf /usr/lib/binfmt.d/qemu-aarch64-static.conf; do
            [ -f "$conf" ] && { cat "$conf" > /proc/sys/fs/binfmt_misc/register || true; break; }
        done
    fi
    [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || die "нет binfmt для aarch64 (установите qemu-user-static)"
fi

WORK="$(mktemp -d /tmp/jiterm-guest.XXXXXX)"
ROOT="$WORK/rootfs"
cleanup() {
    for m in dev/pts dev proc sys; do
        mountpoint -q "$ROOT/$m" 2>/dev/null && umount -l "$ROOT/$m" || true
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

log "Загрузка apk-tools-static ($HOST_ARCH, Alpine v$ALPINE_VERSION)"
INDEX_URL="$ALPINE_MIRROR/v$ALPINE_VERSION/main/$HOST_ARCH/"
APK_PKG="$(curl -fsSL "$INDEX_URL" | grep -o 'apk-tools-static-[0-9][^"]*\.apk' | head -n1)"
[ -n "$APK_PKG" ] || die "не удалось найти apk-tools-static в $INDEX_URL"
curl -fsSL -o "$WORK/apk-tools-static.apk" "$INDEX_URL$APK_PKG"
tar -xzf "$WORK/apk-tools-static.apk" -C "$WORK" sbin/apk.static 2>/dev/null
APK="$WORK/sbin/apk.static"
[ -x "$APK" ] || die "apk.static не распакован"

mkdir -p "$ROOT/etc/apk" "$WORK/apk-cache"
printf '%s\n' "$ALPINE_MIRROR/v$ALPINE_VERSION/main" "$ALPINE_MIRROR/v$ALPINE_VERSION/community" \
    > "$ROOT/etc/apk/repositories"

apk_add() {
    "$APK" --arch aarch64 --root "$ROOT" --allow-untrusted --no-progress \
        --repositories-file "$ROOT/etc/apk/repositories" --cache-dir "$WORK/apk-cache" "$@"
}

log "Базовая система"
apk_add --initdb -U add "${BASE_PACKAGES[@]}"

mount -t proc proc "$ROOT/proc"
mount --rbind /dev "$ROOT/dev"
mount -t sysfs sys "$ROOT/sys"
cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf"

# Модули initramfs: virtio-диск + ext4 (ставим до установки ядра, чтобы mkinitfs их взял)
mkdir -p "$ROOT/etc/mkinitfs"
echo 'features="base ext4 virtio"' > "$ROOT/etc/mkinitfs/mkinitfs.conf"

log "Пакеты: ${PACKAGES[*]}"
apk_add add "${PACKAGES[@]}"

log "Настройка системы"
cp -a "$HERE/overlay/." "$ROOT/"
chmod 700 "$ROOT/root"

echo jiterm > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<'EOF'
127.0.0.1   localhost jiterm
::1         localhost jiterm
EOF
cat > "$ROOT/etc/fstab" <<'EOF'
/dev/vda    /           ext4    rw,relatime,errors=remount-ro   0 1
tmpfs       /tmp        tmpfs   rw,nosuid,nodev,mode=1777       0 0
EOF
printf '%s\n' ttyAMA0 hvc0 hvc1 hvc2 console >> "$ROOT/etc/securetty"

# root: bash, пустой пароль (на случай отключённого автовхода)
sed -i 's|^root:[^:]*:0:0:\([^:]*\):/root:.*$|root:x:0:0:\1:/root:/bin/bash|' "$ROOT/etc/passwd"
sed -i 's|^root:[^:]*:|root::|' "$ROOT/etc/shadow"
echo '/bin/bash' >> "$ROOT/etc/shells"

# Параллельный старт сервисов OpenRC — быстрее загрузка под эмуляцией
sed -i 's|^#\?rc_parallel=.*|rc_parallel="YES"|' "$ROOT/etc/rc.conf" || true

chroot "$ROOT" /bin/sh -e <<'EOF'
for s in devfs dmesg mdev hwdrivers; do rc-update add $s sysinit; done
for s in modules sysctl hostname bootmisc seedrng networking; do
    [ -e /etc/init.d/$s ] && rc-update add $s boot
done
for s in jiterm-agent local; do rc-update add $s default; done
for s in mount-ro killprocs savecache; do rc-update add $s shutdown; done
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
# pip/venv: разрешить pip install вне venv (это личная песочница)
mkdir -p /etc/pip
printf '[global]\nbreak-system-packages = true\n' > /etc/pip.conf
EOF

KVER="$(ls "$ROOT/lib/modules" | head -n1)"
[ -n "$KVER" ] || die "модули ядра не найдены"
# Ядро грузится снаружи (из приложения), поэтому фиксируем версию linux-virt,
# иначе apk upgrade заменит модули и 9p/сеть перестанут грузиться.
KPKG="$(awk '/^P:linux-virt$/{f=1;next} f&&/^V:/{sub(/^V:/,"");print;exit}' "$ROOT/lib/apk/db/installed")"
[ -n "$KPKG" ] && sed -i "s|^linux-virt$|linux-virt=$KPKG|" "$ROOT/etc/apk/world"

mkdir -p "$OUT"
cp "$ROOT/boot/vmlinuz-virt" "$OUT/vmlinuz-virt"
cp "$ROOT/boot/initramfs-virt" "$OUT/initramfs-virt"

log "Очистка"
rm -rf "$ROOT"/var/cache/apk/* "$ROOT"/tmp/* "$ROOT"/root/.cache
: > "$ROOT/etc/resolv.conf"
for m in dev/pts dev proc sys; do
    mountpoint -q "$ROOT/$m" && umount -l "$ROOT/$m" || true
done

log "Создание ext4 ($DISK_SIZE) и qcow2"
rm -f "$WORK/disk.raw"
truncate -s "$DISK_SIZE" "$WORK/disk.raw"
mkfs.ext4 -q -F -L jiterm -m 0 -E lazy_itable_init=1,lazy_journal_init=1 -d "$ROOT" "$WORK/disk.raw"
qemu-img convert -c -O qcow2 "$WORK/disk.raw" "$OUT/rootfs.qcow2"

PY_VER="$(chroot "$ROOT" /usr/bin/python3 -c 'import platform;print(platform.python_version())' 2>/dev/null || echo unknown)"
cat > "$OUT/guest.json" <<EOF
{
  "alpine": "$(cat "$ROOT/etc/alpine-release")",
  "kernel": "$KVER",
  "python": "$PY_VER",
  "diskSize": "$DISK_SIZE",
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

log "Готово: $OUT"
ls -lh "$OUT"
cat "$OUT/guest.json"
