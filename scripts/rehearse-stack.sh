#!/usr/bin/env bash
# The full-stack rehearsal: everything that only a running stack can tell you.
#
# Two checks, in the order that makes a failure readable:
#
#   1. C-12 holds                     scripts/verify-isolation.sh
#   2. every integrations/ export     manage.py rehearse_integrations
#      is called for real
#
# Step 2 is the one that pays TD-1. The BFF's suite mocks the services and each
# service's suite mocks the BFF, so a wire contract is asserted twice and
# checked never: a secret under two names, an issuer nobody passes, a request
# body the route has never accepted — all invisible to a green suite, and all
# visible on the first real call. Deriving the subject list from `__all__` is
# what covers a function with no caller, which is the one most likely to be
# wrong.
#
# Needs the stack up:  make up
set -uo pipefail

cd "$(dirname "$0")/.."

fail=0
step() {
    local name="$1"; shift
    printf '\n\033[1m=== %s ===\033[0m\n' "$name"
    if ! "$@"; then
        printf '\033[31mFAILED: %s\033[0m\n' "$name"
        fail=1
    fi
}

step "C-12 — the gateway is the only ingress" ./scripts/verify-isolation.sh

step "every integrations/ export, called for real" \
    docker compose exec -T bff python manage.py rehearse_integrations

echo
if [ "$fail" -eq 0 ]; then
    printf '\033[32mThe running stack agrees with itself.\033[0m\n'
else
    printf '\033[31mThe running stack disagrees with itself — and a green mocked suite is not an argument.\033[0m\n'
fi
exit "$fail"
