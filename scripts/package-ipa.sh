#!/usr/bin/env bash
# Собирает неподписанный IPA для сайдлоада:
#   1) кладёт фреймворки QEMU в JITerm.app/Frameworks,
#   2) делает «фейковую» подпись ldid с entitlements (их прочитает сайдлоадер),
#   3) упаковывает Payload/JITerm.app в JITerm.ipa.
#
# Использование: scripts/package-ipa.sh <JITerm.app> <каталог-фреймворков> <выходной.ipa>
set -euo pipefail

APP="$(cd "$1" && pwd)"
FRAMEWORKS="$(cd "$2" && pwd)"
OUT="$3"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTITLEMENTS="$HERE/../ios/JITerm.entitlements"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo com.rbxlu.jiterm)"

command -v ldid >/dev/null || { echo "нужен ldid (brew install ldid)" >&2; exit 1; }

for f in vmlinuz-virt initramfs-virt rootfs.qcow2; do
    [ -f "$APP/Guest/$f" ] || { echo "в приложении нет Guest/$f" >&2; exit 1; }
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
TARGET="$STAGE/Payload/$(basename "$APP")"

mkdir -p "$TARGET/Frameworks"
cp -R "$FRAMEWORKS"/*.framework "$TARGET/Frameworks/"
find "$TARGET" -name '_CodeSignature' -type d -prune -exec rm -rf {} +
find "$TARGET" -name 'embedded.mobileprovision' -delete

echo "==> ldid: фреймворки"
for fw in "$TARGET"/Frameworks/*.framework; do
    ldid -S "$fw/$(basename "$fw" .framework)"
done
echo "==> ldid: приложение ($BUNDLE_ID)"
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$TARGET/Info.plist")"
ldid -S"$ENTITLEMENTS" -I"$BUNDLE_ID" "$TARGET/$EXE"
ldid -e "$TARGET/$EXE"

rm -f "$OUT"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
(cd "$STAGE" && zip -qry -9 "$OUT_ABS" Payload -x '*.DS_Store' -x '__MACOSX*')
echo "==> Готово: $OUT_ABS ($(du -h "$OUT_ABS" | cut -f1))"
