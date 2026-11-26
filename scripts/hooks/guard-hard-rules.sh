#!/usr/bin/env bash
# PreToolUse(Bash). The hard rules in CLAUDE.md, as a deny rather than a request.
#
#   1. An agent never merges into `main` and never deploys.
#   2. Production is read-only: `psql` against a production database only with
#      `default_transaction_read_only=on`.
#   3. A secret's value is never printed: no `cat`/`head`/`tail`/`less` of an
#      env file, a real tfvars, Terraform state, or a secrets directory.
#
# These came from the orchestrator prompts of the projects this template was
# extracted from, where they were typed into every session. A rule typed into
# every prompt is a rule that is one forgotten prompt away from being broken.
#
# It matches the command text, like guard-commit-attribution.sh, so it can be
# fooled by indirection; it is a guard rail, not a sandbox. A person who wants
# one of these done runs it themselves.
#
# Pipe-test both directions (scripts/tests/guard-hard-rules.test.sh):
#   printf '%s' '{"tool_input":{"command":"git push origin main"}}' | this   # DENY
#   printf '%s' '{"tool_input":{"command":"git push origin feat/x"}}' | this # SILENT
set -uo pipefail

cmd="$(jq -r '.tool_input.command // ""')"

deny() {
    jq -nc --arg reason "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
}

# --- 1. No merge into main, no deploy ----------------------------------------
# A push whose refspec lands on main: `main`, `HEAD:main`, `x:refs/heads/main`.
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+push([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qE '[[:space:]:](refs/heads/)?main([[:space:]]|$)'; then
    deny "Hard rule: an agent never pushes or merges into main (CLAUDE.md -> Hard rules). Push a branch and open a PR; the owner merges the release."
fi
if printf '%s' "$cmd" | grep -qE 'merge-release\.sh[^;&|]*--merge'; then
    deny "Hard rule: the release merge into main is the owner's. Run merge-release.sh without --merge; it prints the command for them."
fi
if printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+(pr[[:space:]]+merge|api[^;&|]*/merge([[:space:]]|$|"|'"'"'))' \
   && printf '%s' "$cmd" | grep -qE '(--base[= ]main|base=main|[[:space:]]main([[:space:]]|$))'; then
    deny "Hard rule: an agent never merges into main (CLAUDE.md -> Hard rules)."
fi
if printf '%s' "$cmd" | grep -qE 'deploy-prod|deploy-remote\.sh|diagnose-prod'; then
    if printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+(workflow[[:space:]]+run|api[^;&|]*dispatches)|(^|[;&|[:space:]])(bash|sh)[[:space:]]+(-[^n[:space:]][^[:space:]]*[[:space:]]+)*[^[:space:]]*deploy-remote\.sh|ssh[^;&|]*deploy-remote\.sh|<[[:space:]]*\.github/scripts/deploy-remote\.sh'; then
        deny "Hard rule: an agent never deploys (CLAUDE.md -> Hard rules). Production deploys run from the merge to main, which the owner makes."
    fi
fi

# --- 2. Production is read-only ----------------------------------------------
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])psql([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qiE 'prod'; then
    if ! printf '%s' "$cmd" | grep -qE 'default_transaction_read_only[[:space:]]*=[[:space:]]*on'; then
        deny "Hard rule: production is read-only. Connect with PGOPTIONS='-c default_transaction_read_only=on' (CLAUDE.md -> Hard rules)."
    fi
fi

# --- 3. Never print a secret ---------------------------------------------------
if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(cat|head|tail|less|more|bat|strings|xxd|od)[[:space:]]' \
   && printf '%s' "$cmd" | grep -qE '(^|[[:space:]/])\.env([[:space:]]|$|\.[a-z]+([[:space:]]|$))|[^[:space:]]+\.env([[:space:]]|$)|terraform\.tfvars([[:space:]]|$)|\.tfstate|/secrets/|\.tfplan'; then
    if ! printf '%s' "$cmd" | grep -qE '\.example([[:space:]]|$)'; then
        deny "Hard rule: a secret's value is never shown (CLAUDE.md -> Hard rules). Check a name exists with grep -c '^NAME=' instead of printing the file."
    fi
fi

exit 0
