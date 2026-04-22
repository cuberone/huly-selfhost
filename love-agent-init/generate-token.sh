#!/bin/sh
# Generate the PLATFORM_TOKEN the upstream love-agent needs to POST
# transcripts to aibot's /love/transcript endpoint.
#
# aibot rejects the request unless token.account == aibot's own personUuid.
# That UUID is assigned by the accounts service when aibot signs up on first
# start, so we look it up by the bot's well-known social key. We authenticate
# that lookup with a forged system token (systemAccountUuid is a constant).
#
# The resulting token is written to /shared/platform_token and consumed by
# the love-agent container via `command:` override.
set -eu

SECRET="${SECRET:?SECRET is required}"
ACCOUNTS_URL="${ACCOUNTS_URL:-http://account:3000}"
# hcengineering/platform: foundations/core/packages/core/src/component.ts
SYSTEM_ACCOUNT_UUID="1749089e-22e6-48de-af4e-165e18fbd2f9"
# hcengineering/platform: plugins/ai-bot/src/index.ts
AI_BOT_SOCIAL_KEY="email:huly.ai.bot@hc.engineering"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

sign_jwt() {
  payload="$1"
  header='{"typ":"JWT","alg":"HS256"}'
  h=$(printf '%s' "$header" | b64url)
  p=$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$sig"
}

SYSTEM_TOKEN=$(sign_jwt "{\"account\":\"$SYSTEM_ACCOUNT_UUID\",\"extra\":{\"service\":\"aibot\"}}")

echo "Looking up aibot personUuid at $ACCOUNTS_URL..."

UUID=""
i=0
while [ "$i" -lt 60 ]; do
  i=$((i + 1))
  RESP=$(curl -fsS -X POST "$ACCOUNTS_URL/" \
    -H "Authorization: Bearer $SYSTEM_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{"method":"findPersonBySocialKey","params":{"socialString":"'"$AI_BOT_SOCIAL_KEY"'","requireAccount":false}}' \
    2>/dev/null || true)
  # Response shape: {"result":"<uuid>"} on hit, {"result":null} before aibot signs up
  UUID=$(printf '%s' "$RESP" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
  if [ -n "$UUID" ]; then
    break
  fi
  echo "  attempt $i: aibot account not yet registered; retrying in 5s..."
  sleep 5
done

if [ -z "$UUID" ]; then
  echo "ERROR: failed to resolve aibot personUuid after $i attempts" >&2
  echo "last response: $RESP" >&2
  exit 1
fi

echo "aibot personUuid: $UUID"

TOKEN=$(sign_jwt "{\"account\":\"$UUID\",\"extra\":{\"service\":\"aibot\"}}")

mkdir -p /shared
printf '%s' "$TOKEN" > /shared/platform_token
chmod 644 /shared/platform_token

echo "Wrote /shared/platform_token ($(wc -c < /shared/platform_token) bytes)"
