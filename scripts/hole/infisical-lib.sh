#!/bin/sh
# Shared Infisical helpers for The HOLE Foundation deployment scripts.
# Uses only curl + jq (both ship in the Paperclip image); no Infisical CLI.
#
# Env:
#   INFISICAL_API_URL        default https://app.infisical.com (set for self-hosted/EU)
#   INFISICAL_CLIENT_ID      machine identity (Universal Auth) client id
#   INFISICAL_CLIENT_SECRET  machine identity (Universal Auth) client secret
#   INFISICAL_PROJECT_ID     project id
#   INFISICAL_ENVIRONMENT    environment slug, default prod

# curl with "Authorization: Bearer $1" passed on fd 3, so the token never appears in the process list.
curl_bearer() {
    _tok="$1"; shift
    curl -H @/dev/fd/3 "$@" 3<<EOF
Authorization: Bearer $_tok
EOF
}

infisical_configured() {
    [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ] && [ -n "${INFISICAL_PROJECT_ID:-}" ]
}

# Prints the raw JSON secrets response for folder $1 to stdout. Exits non-zero on any failure.
infisical_fetch_secrets() {
    secret_path="$1"
    api="${INFISICAL_API_URL:-https://app.infisical.com}"
    api="${api%/}"

    # Client secret goes over stdin, not argv.
    token="$(printf '%s' "$INFISICAL_CLIENT_SECRET" | curl -fsS --retry 3 -X POST "$api/api/v1/auth/universal-auth/login" \
        --data-urlencode "clientId=$INFISICAL_CLIENT_ID" \
        --data-urlencode 'clientSecret@-' | jq -er '.accessToken')" || {
        echo "infisical: universal-auth login failed at $api" >&2
        return 1
    }

    curl_bearer "$token" -fsS --retry 3 --get "$api/api/v4/secrets" \
        --data-urlencode "projectId=$INFISICAL_PROJECT_ID" \
        --data-urlencode "environment=${INFISICAL_ENVIRONMENT:-prod}" \
        --data-urlencode "secretPath=$secret_path" \
        --data-urlencode "expandSecretReferences=true" || {
        echo "infisical: failed to list secrets at path $secret_path" >&2
        return 1
    }
}
