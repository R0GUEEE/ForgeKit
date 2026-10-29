#!/bin/sh
# Builds build/ForgeKit.dylib with the Xcode iPhoneOS SDK (no Theos required).
set -eu
SDK="${SDK:-$(xcrun --sdk iphoneos --show-sdk-path)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
xcrun --sdk iphoneos clang \
  -isysroot "$SDK" \
  -arch arm64 -arch arm64e \
  -miphoneos-version-min=14.0 \
  -fobjc-arc -O2 -fvisibility=hidden -dynamiclib \
  -install_name @rpath/ForgeKit.dylib \
  -ISources \
  "$ROOT"/Sources/*.m \
  -o "$ROOT/build/ForgeKit.dylib" \
  -framework Foundation -framework UIKit -framework CoreGraphics \
  -framework QuartzCore -framework JavaScriptCore -framework Security \
  -framework CoreImage -framework AVFoundation -lsqlite3 -lz
lipo -info "$ROOT/build/ForgeKit.dylib"
echo "built $ROOT/build/ForgeKit.dylib"
