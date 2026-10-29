#!/bin/sh
# Builds a rootless .deb from the locally built universal dylib.
# Usage: tools/make-deb.sh [version]
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(grep -i '^Version:' "$ROOT/control" | cut -d' ' -f2-)}"
OUT="$ROOT/ForgeKit_${VERSION}_iphoneos-arm64.deb"
STAGE="$ROOT/.deb-stage"

rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/var/jb/usr/lib" \
         "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
cp "$ROOT/ForgeKit.dylib" "$STAGE/var/jb/usr/lib/ForgeKit.dylib"
cp "$ROOT/ForgeKit.plist" "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/ForgeKit.plist"
chmod 755 "$STAGE/var/jb/usr/lib/ForgeKit.dylib"
chmod 644 "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/ForgeKit.plist"
chmod -R 755 "$STAGE/var" "$STAGE/var/jb"
chmod 755 "$STAGE" "$STAGE/DEBIAN"

sed -e "s/^Version:.*/Version: $VERSION/" "$ROOT/control" > "$STAGE/DEBIAN/control"
chmod 644 "$STAGE/DEBIAN/control"

dpkg-deb -Zgzip --build "$STAGE" "$OUT"
rm -rf "$STAGE"
echo "built $OUT"
