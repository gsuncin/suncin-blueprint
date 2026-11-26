#!/usr/bin/env bash
# The app's page-and-asset rate limit must hold one office's cold load of the SPA.
#
# Every file of `acme-web` goes through `app-chain` → `ratelimit-app`, keyed on the
# source address. A team leaves through one NAT address, and a deploy renames every
# chunk, so the first minute after a deploy is the whole team re-downloading the bundle
# at once. At 30/min with a burst of 20 that answered "Too Many Requests" in graav-app on
# 2026-11-09 (176 files in its bundle). The floor is `ratelimit-api`'s, 120/min, burst 60
# (graav-app R-2026-11-09-7c41e2).
set -euo pipefail

cd "$(dirname "$0")/../.."
FILE=acme-gateway/traefik/dynamic/middlewares.yml
failures=0

value_of() { # middleware key
  awk -v mw="    $1:" -v key="$2:" '
    $0 == mw { inside = 1; next }
    inside && /^    [a-z]/ { inside = 0 }
    inside && $1 == key { print $2; exit }
  ' "$FILE"
}

expect_at_least() { # middleware key floor
  local got
  got=$(value_of "$1" "$2")
  if [[ -z "$got" || "$got" -lt "$3" ]]; then
    echo "FAIL: $1 $2 is '${got:-missing}', expected at least $3"
    failures=$((failures + 1))
  else
    echo "ok: $1 $2 = $got (>= $3)"
  fi
}

expect_at_least ratelimit-app average 120
expect_at_least ratelimit-app burst 60
# The brute-force guard must not be loosened along with it.
login_avg=$(value_of ratelimit-auth average)
if [[ "$login_avg" != "5" ]]; then
  echo "FAIL: ratelimit-auth average is '$login_avg', expected 5"
  failures=$((failures + 1))
else
  echo "ok: ratelimit-auth average = 5"
fi

if (( failures > 0 )); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
