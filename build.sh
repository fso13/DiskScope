#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
CACHE="$ROOT/.cache/clang"
export CLANG_MODULE_CACHE_PATH="$CACHE"

VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
UNIVERSAL="${UNIVERSAL:-0}"

COMMON_FLAGS=(
  --disable-sandbox
  --cache-path "$ROOT/.cache/swiftpm"
  -Xswiftc -module-cache-path
  -Xswiftc "$CACHE"
)

if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Building DiskScope ${VERSION} (universal: arm64 + x86_64)"
  SCRATCH="$ROOT/.build/universal"
  swift build -c release --arch arm64 --arch x86_64 \
    --scratch-path "$SCRATCH" "${COMMON_FLAGS[@]}"
  BINARY="$SCRATCH/out/Products/Release/DiskScope"
  if [ ! -f "$BINARY" ]; then
    BINARY="$(find "$SCRATCH" -type f -name DiskScope -path "*Products/Release*" ! -path "*.dSYM/*" -print -quit)"
  fi
  if [ -z "${BINARY:-}" ] || [ ! -f "$BINARY" ]; then
    echo "error: universal DiskScope binary not found" >&2
    exit 1
  fi
  if ! lipo -info "$BINARY" | grep -Eq 'arm64.*x86_64|x86_64.*arm64'; then
    echo "error: expected a universal binary, got:" >&2
    lipo -info "$BINARY" >&2
    exit 1
  fi
else
  echo "==> Building DiskScope ${VERSION} (host architecture)"
  swift build -c release --scratch-path "$ROOT/.build" "${COMMON_FLAGS[@]}"
  BINARY="$ROOT/.build/release/DiskScope"
fi

APP="$ROOT/dist/DiskScope.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/DiskScope"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

ICON="$ROOT/Support/icon-1024.png"
if [ ! -f "$ICON" ]; then
  echo "==> Generating app icon"
  swiftc -module-cache-path "$CACHE" "$ROOT/Support/make_icon.swift" -o "$ROOT/.build/make-icon"
  "$ROOT/.build/make-icon" "$ICON"
fi

ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for spec in \
  "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" \
  "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" \
  "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  size="${spec%%:*}"
  name="${spec##*:}"
  sips -z "$size" "$size" "$ICON" --out "$ICONSET/$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

lipo -info "$APP/Contents/MacOS/DiskScope"

echo "==> Packaging zip"
rm -f "$ROOT/dist/DiskScope.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/DiskScope.zip"

echo ""
echo "Built:   $APP"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Zip:     $ROOT/dist/DiskScope.zip"
echo "Open:    open \"$APP\""
