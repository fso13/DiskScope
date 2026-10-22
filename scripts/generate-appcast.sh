#!/usr/bin/env bash
# Generates a signed Sparkle appcast from release archives in dist/.
# The Sparkle private key must be in the keychain, or imported first with:
#   generate_keys -f sparkle_private_key
# Usage:
#   VERSION=1.2.0 ./scripts/generate-appcast.sh dist
set -euo pipefail
cd "$(dirname "$0")/.."

DIST="${1:-dist}"
VERSION="${VERSION:?VERSION is required}"
PREFIX="${DOWNLOAD_PREFIX:-https://github.com/fso13/DiskScope/releases/download/v${VERSION}/}"

TOOL="${SPARKLE_GENERATE_APPCAST:-}"
if [ -z "$TOOL" ]; then
  for candidate in \
    .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    .build/checkouts/Sparkle/generate_appcast \
    /opt/homebrew/bin/generate_appcast \
    /usr/local/bin/generate_appcast; do
    if [ -x "$candidate" ]; then TOOL="$candidate"; break; fi
  done
fi
if [ -z "$TOOL" ] || [ ! -x "$TOOL" ]; then
  echo "error: generate_appcast not found; set SPARKLE_GENERATE_APPCAST" >&2
  exit 1
fi

ARCHIVE="$DIST/DiskScope-${VERSION}-macos-universal.zip"
if [ ! -f "$ARCHIVE" ]; then
  echo "error: update archive not found: $ARCHIVE" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ARCHIVE" "$STAGE/"

echo "==> Generating appcast for $ARCHIVE (prefix $PREFIX)"
"$TOOL" \
  --download-url-prefix "$PREFIX" \
  --link "https://github.com/fso13/DiskScope" \
  --embed-release-notes \
  "$STAGE"

cp "$STAGE/appcast.xml" "$DIST/appcast.xml"
echo "==> $DIST/appcast.xml"
