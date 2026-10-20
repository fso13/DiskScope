#!/usr/bin/env bash
# Copies screenshots and the app icon into docs/assets.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p docs/assets/screenshots
if compgen -G "snapshots/*.png" >/dev/null; then
  cp snapshots/*.png docs/assets/screenshots/
fi

if [ -f Support/icon-1024.png ]; then
  cp Support/icon-1024.png docs/assets/icon.png
fi

echo "Docs assets synced from snapshots/ and Support/icon-1024.png"
