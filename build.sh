#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
CACHE="$ROOT/.cache/clang"
export CLANG_MODULE_CACHE_PATH="$CACHE"

VERSION="${VERSION:-2.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-20}"
UNIVERSAL="${UNIVERSAL:-0}"
SKIP_DMG="${SKIP_DMG:-0}"

COMMON_FLAGS=(
  --disable-sandbox
  --cache-path "$ROOT/.cache/swiftpm"
  -Xswiftc -module-cache-path
  -Xswiftc "$CACHE"
)

if [ "$UNIVERSAL" = "1" ]; then
  echo "==> Building DiskScope ${VERSION} (universal: arm64 + x86_64)"
  SCRATCH="$ROOT/.build/universal"
  swift build -c release --product DiskScope --arch arm64 --arch x86_64 \
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
  swift build -c release --product DiskScope --scratch-path "$ROOT/.build" "${COMMON_FLAGS[@]}"
  BINARY="$ROOT/.build/release/DiskScope"
fi

APP="$ROOT/dist/DiskScope.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/DiskScope"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/fso13/DiskScope/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-__SPARKLE_PUBLIC_KEY__}"
/usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
if [ -d "$ROOT/Sources/DiskScopeKit/Resources/en.lproj" ]; then
  cp -R "$ROOT/Sources/DiskScopeKit/Resources/en.lproj" "$APP/Contents/Resources/"
fi
RESOURCE_BUNDLE="$(dirname "$BINARY")/DiskScope_DiskScopeKit.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

ICON="$ROOT/Support/icon-1024.png"
if [ ! -f "$ICON" ]; then
  echo "==> Generating app icon"
  swiftc -module-cache-path "$CACHE" "$ROOT/Support/make_icon.swift" -o "$ROOT/.build/make-icon"
  "$ROOT/.build/make-icon" "$ICON"
fi

mkdir -p "$APP/Contents/Frameworks"
SPARKLE_FRAMEWORK="$(dirname "$BINARY")/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/DiskScope" 2>/dev/null || true
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

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "==> Signing (ad-hoc)"
  codesign --force --deep --sign - "$APP" >/dev/null
else
  echo "==> Signing with $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" >/dev/null
fi
codesign --verify --deep --strict "$APP"

lipo -info "$APP/Contents/MacOS/DiskScope"

echo "==> Packaging zip"
rm -f "$ROOT/dist/DiskScope.zip"
ditto -c -k --keepParent "$APP" "$ROOT/dist/DiskScope.zip"

if [ "$SKIP_DMG" = "1" ]; then
  echo "==> Skipping DMG (SKIP_DMG=1)"
else
  echo "==> Packaging DMG installer"
  DMG="$ROOT/dist/DiskScope.dmg"
  STAGING="$ROOT/.build/dmg"
  rm -rf "$STAGING" "$DMG"
  mkdir -p "$STAGING/.background"
  ditto "$APP" "$STAGING/DiskScope.app"
  ln -s /Applications "$STAGING/Applications"
  cp "$ROOT/Support/dmg/background.png" "$STAGING/.background/background.png"
  cp "$ROOT/Support/dmg/DS_Store" "$STAGING/.DS_Store"
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$STAGING"
    fi
  fi
  hdiutil create -volname "DiskScope" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
  hdiutil verify "$DMG" >/dev/null
fi

echo ""
echo "Built:   $APP"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Zip:     $ROOT/dist/DiskScope.zip"
if [ "$SKIP_DMG" = "1" ]; then
  echo "DMG:     skipped"
else
  echo "DMG:     $DMG"
fi
echo "Open:    open \"$APP\""
