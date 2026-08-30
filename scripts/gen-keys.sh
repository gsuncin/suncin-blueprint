#!/usr/bin/env bash
# Generate the secrets that cannot be typed by hand, into .env.
#
# Idempotent: an existing non-empty value is left alone, so running this twice
# does not invalidate every session and every stored credential.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=".env"

[ -f "$ENV_FILE" ] || { cp .env.example "$ENV_FILE"; echo "created $ENV_FILE from .env.example"; }

# set_secret <KEY> <generator command>
set_secret() {
    local key="$1" generator="$2" current
    current="$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2- || true)"

    # A placeholder from .env.example is not a value. Without this check the
    # first run leaves SECRET_KEY as "change-me..." and nothing complains until
    # someone reads the deploy checklist.
    case "$current" in
        ""|change-me*|CHANGE_ME*) ;;
        *) echo "$key: already set, leaving it alone"; return ;;
    esac

    local value
    value="$(eval "$generator")"

    if grep -qE "^${key}=" "$ENV_FILE"; then
        # A literal | in a generated value would break the sed delimiter, and
        # base64 never emits one — but neither does it emit \x01.
        python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().splitlines()
out = [f"{key}={value}" if line.startswith(f"{key}=") else line for line in lines]
open(path, "w").write("\n".join(out) + "\n")
PY
    else
        printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
    echo "$key: generated"
}

# RS256 signing key. The BFF signs with it; the gateway fetches only the
# public half from the JWKS endpoint and can therefore never mint a token.
set_secret JWT_PRIVATE_KEY_B64 \
    "openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null | base64 | tr -d '\n'"

# Fernet key: 32 raw bytes, url-safe base64. Anything else fails at import.
set_secret PROVIDER_CREDENTIAL_ENCRYPTION_KEY \
    "python3 -c \"import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())\""

set_secret GATEWAY_TOKEN "openssl rand -hex 32"

set_secret EXAMPLE_SERVICE_JWT_SECRET "openssl rand -hex 32"

set_secret SECRET_KEY "openssl rand -base64 48 | tr -d '\n'"

echo
echo "Done. $ENV_FILE is gitignored and must stay that way."
