#!/usr/bin/env bash
# Mint a visitor JWT for the iOS sample (POST /api/v1/chat/auth).
#
# Usage:
#   CHATBOT_API_KEY=... CHATBOT_ID=shop-bot ./scripts/mint-visitor-token.sh
#   ENV=development CHATBOT_API_KEY=... CHATBOT_ID=... ./scripts/mint-visitor-token.sh
#   ENV=local CHATBOT_API_KEY=... CHATBOT_ID=... ./scripts/mint-visitor-token.sh
#   API_BASE_URL=https://custom.example ./scripts/mint-visitor-token.sh   # overrides ENV
#
# ENV: production (default) | development | local
# Prints the token to stdout. Keep the API key off the device — this script is the host.
set -euo pipefail

CHATBOT_API_KEY="${CHATBOT_API_KEY:?set CHATBOT_API_KEY}"
CHATBOT_ID="${CHATBOT_ID:?set CHATBOT_ID}"
ENV="${ENV:-production}"

if [[ -z "${API_BASE_URL:-}" ]]; then
  case "$ENV" in
    production) API_BASE_URL="https://api.dialogintelligens.dk" ;;
    development) API_BASE_URL="https://dev.api.dialogintelligens.dk" ;;
    local) API_BASE_URL="http://127.0.0.1:3000" ;;
    *)
      echo "unknown ENV='$ENV' (use production|development|local, or set API_BASE_URL)" >&2
      exit 2
      ;;
  esac
fi

response="$(
  curl -sS -u "${CHATBOT_API_KEY}:" \
    -H "Content-Type: application/json" \
    -X POST "${API_BASE_URL%/}/api/v1/chat/auth" \
    -d "{\"chatbot_id\":\"${CHATBOT_ID}\"}"
)"

token="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("token") or "")' <<<"$response")"
if [[ -z "$token" ]]; then
  echo "auth failed (${API_BASE_URL}):" >&2
  echo "$response" >&2
  exit 1
fi

echo "$token"
