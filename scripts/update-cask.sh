#!/usr/bin/env bash
# Updates version and SHA-256 in the Homebrew cask.
# Usage: VERSION=1.2.0 SHA256=<dmg-sha> ./scripts/update-cask.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:?VERSION is required}"
SHA256="${SHA256:?SHA256 is required}"
CASK="Casks/diskscope.rb"

if [ ! -f "$CASK" ]; then
  echo "error: $CASK not found" >&2
  exit 1
fi

/usr/bin/sed -i '' -E "s/version \"[^\"]+\"/version \"${VERSION}\"/" "$CASK"
/usr/bin/sed -i '' -E "s/sha256 \"[^\"]+\"/sha256 \"${SHA256}\"/" "$CASK"
ruby -c "$CASK"
echo "Updated $CASK to $VERSION"
