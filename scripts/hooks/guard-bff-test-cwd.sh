#!/usr/bin/env bash
# PreToolUse(Bash). Denies a Django test run that is not launched from INSIDE
# acme-bff.
#
# Why this is a hook and not a warning: CLAUDE.md says it in two places and it
# still happens. `python acme-bff/manage.py test` from the repo root discovers
# nothing and exits `Ran 0 tests ... OK` — a green summary with nothing behind
# it. A warning does not stop a command; a hook does.
#
# Pipe-test both directions:
#   echo '{"tool_input":{"command":"python acme-bff/manage.py test"}}'       | this  # must DENY
#   echo '{"tool_input":{"command":"cd acme-bff && python manage.py test"}}' | this  # must be SILENT
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

printf '%s' "$cmd" | grep -qE 'manage\.py +test' || exit 0
# The only shape that works is one that changes directory first. `cd` up to the
# next command separator is what run-all-tests.sh does, and it is the reason
# that script is correct.
printf '%s' "$cmd" | grep -qE 'cd +[^&;|]*acme-bff' && exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "Run the Django suite from INSIDE acme-bff. From the repo root Django discovers zero tests and exits OK — a green summary with nothing behind it (CLAUDE.md, \"Running the suites\"). Use: cd acme-bff && DEBUG=True DB_NAME=<scratch> .venv/bin/python manage.py test — or ./scripts/run-all-tests.sh, which cds for you."
  }
}'
