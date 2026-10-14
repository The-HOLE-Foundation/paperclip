#!/bin/sh
# Copy secrets from an Infisical folder into a Paperclip company's secret store.
# Missing keys are created; existing keys are rotated to the Infisical value.
#
# Run inside the paperclip container (it already has the Infisical env):
#   docker compose exec paperclip sh /app/scripts/hole/infisical-import-secrets.sh
#
# Env (in addition to infisical-lib.sh):
#   PAPERCLIP_BOARD_API_KEY   board API key (Settings -> API keys)
#   PAPERCLIP_COMPANY_ID      target company id
#   INFISICAL_IMPORT_PATH     Infisical folder to import, default /paperclip
#   PAPERCLIP_API_URL         default http://127.0.0.1:3100
set -eu

. "$(dirname "$0")/infisical-lib.sh"

infisical_configured || { echo "INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET and INFISICAL_PROJECT_ID are required" >&2; exit 1; }
: "${PAPERCLIP_BOARD_API_KEY:?PAPERCLIP_BOARD_API_KEY is required}"
: "${PAPERCLIP_COMPANY_ID:?PAPERCLIP_COMPANY_ID is required}"
api="${PAPERCLIP_API_URL:-http://127.0.0.1:3100}"
api="${api%/}/api"
auth="Authorization: Bearer $PAPERCLIP_BOARD_API_KEY"

existing="$(curl -fsS -H "$auth" "$api/companies/$PAPERCLIP_COMPANY_ID/secrets")"
source_json="$(infisical_fetch_secrets "${INFISICAL_IMPORT_PATH:-/paperclip}")"

# One compact JSON object per line: {key, value}. Values never touch argv or disk.
printf '%s' "$source_json" | jq -c '.secrets[] | {key: .secretKey, value: .secretValue}' | while IFS= read -r row; do
    key="$(printf '%s' "$row" | jq -r '.key')"
    if ! printf '%s' "$key" | grep -Eq '^[A-Za-z0-9_.-]{1,120}$' || [ -z "$(printf '%s' "$row" | jq -r '.value')" ]; then
        echo "skip  $key (invalid key or empty value)" >&2
        continue
    fi
    id="$(printf '%s' "$existing" | jq -r --arg k "$key" 'map(select(.key == $k and .scope == "company")) | first | .id // empty')"
    if [ -n "$id" ]; then
        printf '%s' "$row" | jq -c '{value}' | curl -fsS -o /dev/null -X POST -H "$auth" -H 'Content-Type: application/json' \
            --data-binary @- "$api/secrets/$id/rotate"
        echo "rotate $key" >&2
    else
        printf '%s' "$row" | jq -c '{name: .key, key: .key, value: .value, description: "Imported from Infisical"}' \
            | curl -fsS -o /dev/null -X POST -H "$auth" -H 'Content-Type: application/json' \
            --data-binary @- "$api/companies/$PAPERCLIP_COMPANY_ID/secrets"
        echo "create $key" >&2
    fi
done
