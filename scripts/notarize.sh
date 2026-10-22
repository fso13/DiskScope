#!/usr/bin/env bash
# Submits the signed app/DMG to Apple's notary service and staples the ticket.
# Usage:
#   APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... \
#     ./scripts/notarize.sh dist/DiskScope.app dist/DiskScope.dmg
# Or with a stored notarytool profile:
#   NOTARY_PROFILE=DiskScope ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/DiskScope.app}"
DMG="${2:-dist/DiskScope.dmg}"

if [ ! -d "$APP" ]; then
  echo "error: app not found: $APP" >&2
  exit 1
fi
if [ ! -f "$DMG" ]; then
  echo "error: disk image not found: $DMG" >&2
  exit 1
fi

if [ -n "${NOTARY_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$NOTARY_PROFILE")
else
  : "${APPLE_ID:?APPLE_ID is required (or set NOTARY_PROFILE)}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required (or set NOTARY_PROFILE)}"
  : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required (or set NOTARY_PROFILE)}"
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi

echo "==> Submitting $DMG to notarytool"
xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait

echo "==> Stapling app and DMG"
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper check"
spctl -a -vv --type execute "$APP"
echo "Notarization complete."
