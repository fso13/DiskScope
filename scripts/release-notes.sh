#!/usr/bin/env bash
# Extracts the CHANGELOG section for a tag and prints it as release notes.
# Usage: scripts/release-notes.sh v1.2.3 [CHANGELOG.md]
set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <tag> [changelog]" >&2
  exit 2
fi

VERSION="${TAG#v}"
CHANGELOG="${2:-CHANGELOG.md}"

if [ ! -f "$CHANGELOG" ]; then
  echo "warning: $CHANGELOG not found, falling back to git log" >&2
  CHANGELOG=""
fi

NOTES=""
if [ -n "$CHANGELOG" ]; then
  NOTES="$(awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { found = 1; next }
    found && /^## \[/ { exit }
    found { print }
  ' "$CHANGELOG")"
fi

if printf '%s' "$NOTES" | grep -q '[^[:space:]]'; then
  printf '%s\n' "$NOTES" | awk 'NF { found = 1 } found'
  exit 0
fi

echo "> Для тега \`$TAG\` не найден раздел в CHANGELOG.md — ниже автоматический список коммитов."
echo
echo "### Коммиты"
echo

if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  PREVIOUS="$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)"
  if [ -n "$PREVIOUS" ]; then
    git log --no-merges --max-count=100 --pretty=format:'- %s' "${PREVIOUS}..HEAD"
    echo
  else
    git log --no-merges --max-count=30 --pretty=format:'- %s' HEAD
    echo
  fi
else
  echo "- Изменения см. в CHANGELOG.md."
fi
