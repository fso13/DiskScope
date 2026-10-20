#!/usr/bin/env bash
# Publishes the wiki sources from wiki/ into the GitHub wiki repository.
#
# GitHub does not expose an API for creating the first wiki page. If the wiki
# has never been opened, create any first page in the browser, then re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIKI_URL="${WIKI_URL:-https://github.com/fso13/DiskScope.wiki.git}"
TMP="$(mktemp -d)"
CLONE_LOG="$(mktemp)"
cleanup() {
  rm -rf "$TMP" "$CLONE_LOG"
}
trap cleanup EXIT

echo "Cloning $WIKI_URL"
if ! GIT_TERMINAL_PROMPT=0 git clone "$WIKI_URL" "$TMP" >"$CLONE_LOG" 2>&1; then
  cat >&2 <<'MSG'
Не удалось склонировать GitHub wiki.

GitHub не даёт создать первую страницу wiki через API или git:
1. Откройте https://github.com/fso13/DiskScope/wiki
2. Нажмите «Create the first page» и сохраните любую страницу.
3. Повторите: ./scripts/publish-wiki.sh

Если вики уже создана, проверьте доступ к github.com и права токена.
MSG
  cat "$CLONE_LOG" >&2
  exit 1
fi

rsync -a --delete --exclude='.git' "$ROOT/wiki/" "$TMP/"

cd "$TMP"
if git diff --quiet && git diff --cached --quiet; then
  echo "Wiki already up to date."
  exit 0
fi

git add -A
git -c user.name='DiskScope' -c user.email='noreply@github.com' \
  commit -m "docs: publish DiskScope wiki"
git push origin HEAD
echo "Wiki published: https://github.com/fso13/DiskScope/wiki"
