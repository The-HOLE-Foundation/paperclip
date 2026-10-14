#!/bin/sh
# Entrypoint wrapper: load instance bootstrap secrets from Infisical into the
# environment, verify required variables, then exec the normal entrypoint.
#
#   tini -- sh infisical-bootstrap.sh docker-entrypoint.sh node ... server/dist/index.js
#
# Env (in addition to infisical-lib.sh):
#   INFISICAL_BOOTSTRAP_PATH  folder holding instance env vars, default /bootstrap
#   PAPERCLIP_REQUIRED_ENV    space-separated names that must be non-empty after
#                             bootstrap; startup is refused otherwise
#
# A variable already set to a non-empty value in the container environment wins
# over Infisical, so a one-off override never needs an Infisical edit.
set -e

. "$(dirname "$0")/infisical-lib.sh"

if infisical_configured; then
    json="$(infisical_fetch_secrets "${INFISICAL_BOOTSTRAP_PATH:-/bootstrap}")"
    # @sh quotes values safely; keys that are not shell identifiers are skipped.
    exports="$(printf '%s' "$json" | jq -r '
        .secrets[]
        | select(.secretKey | test("^[A-Za-z_][A-Za-z0-9_]*$"))
        | "[ -n \"${\(.secretKey):-}\" ] || export \(.secretKey)=\(.secretValue | @sh)"')"
    eval "$exports"
    echo "infisical-bootstrap: loaded $(printf '%s' "$json" | jq '.secrets | length') secrets from ${INFISICAL_BOOTSTRAP_PATH:-/bootstrap}" >&2
    unset json exports
else
    echo "infisical-bootstrap: INFISICAL_CLIENT_ID/SECRET/PROJECT_ID not set; skipping Infisical" >&2
fi

missing=""
for name in ${PAPERCLIP_REQUIRED_ENV:-}; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || missing="$missing $name"
done
unset value
if [ -n "$missing" ]; then
    echo "infisical-bootstrap: refusing to start; required env missing:$missing" >&2
    exit 1
fi

# Drop the machine-identity credentials before handing off to Paperclip and its agents.
unset INFISICAL_CLIENT_SECRET
exec "$@"
