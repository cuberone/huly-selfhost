#!/bin/sh
# Mints aibot's PLATFORM_TOKEN for love-agent. See CLAUDE.md "love-agent token bootstrap".
set -eu

MAX_ATTEMPTS="${MAX_ATTEMPTS:-60}"
SLEEP_SECS="${SLEEP_SECS:-5}"
BOT_EMAIL="${BOT_EMAIL:-huly.ai.bot@hc.engineering}"
TOKEN_PATH="${TOKEN_PATH:-/shared/platform_token}"
# Workspace arg is validated as a UUID by the tool CLI but ignored by aibot's
# /love/transcript handler — only the `account` claim is checked.
NIL_WORKSPACE="00000000-0000-0000-0000-000000000000"

i=0
while [ "$i" -lt "$MAX_ATTEMPTS" ]; do
  i=$((i + 1))
  TOKEN=$(node /usr/src/app/bundle.js generate-token "$BOT_EMAIL" "$NIL_WORKSPACE" 2>/tmp/err || true)
  # generate-token exits 0 with empty stdout when the socialId row is missing,
  # so check the decoded `account` claim shape instead of the exit code.
  ACCOUNT=$(printf '%s' "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | sed -n 's/.*"account":"\([^"]*\)".*/\1/p')
  case "$ACCOUNT" in
    [0-9a-f]*-[0-9a-f]*-*)
      printf '%s' "$TOKEN" > "$TOKEN_PATH"
      echo "Wrote $TOKEN_PATH (account=$ACCOUNT)"
      exit 0
      ;;
    *)
      echo "attempt $i: no token yet; tool stderr:"
      head -5 /tmp/err | sed 's/^/  /'
      sleep "$SLEEP_SECS"
      ;;
  esac
done
echo "ERROR: failed to resolve aibot personUuid after $i attempts" >&2
exit 1
