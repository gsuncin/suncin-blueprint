#!/usr/bin/env bash
# Both directions for scripts/hooks/guard-hard-rules.sh: what it must deny, and
# the everyday commands it must leave alone (a guard that denies `git push` of a
# feature branch gets switched off within a day).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/../hooks" && pwd)/guard-hard-rules.sh"
passed=0
failed=0

run_hook() { jq -nc --arg c "$1" '{tool_input: {command: $c}}' | "$HOOK"; }

expect_deny() {
    if run_hook "$1" | grep -q '"permissionDecision":"deny"'; then
        printf '    ok   denies: %s\n' "$1"; passed=$((passed + 1))
    else
        printf '    FAIL should deny: %s\n' "$1"; failed=$((failed + 1))
    fi
}
expect_allow() {
    if [ -z "$(run_hook "$1")" ]; then
        printf '    ok   allows: %s\n' "$1"; passed=$((passed + 1))
    else
        printf '    FAIL should allow: %s\n' "$1"; failed=$((failed + 1))
    fi
}

echo "=== 1. no merge into main, no deploy"
expect_deny  'git push origin main'
expect_deny  'git push origin HEAD:main'
expect_deny  'git push -u origin feat/x:refs/heads/main'
expect_deny  'git -C repo push origin main'
expect_deny  './scripts/merge-release.sh 42 --merge'
expect_deny  'gh pr merge 42 --merge --base main'
expect_deny  'gh workflow run deploy-prod.yml -f image_tag=sha-abc1234'
expect_deny  'gh api -X POST repos/o/r/actions/workflows/deploy-prod.yml/dispatches -f ref=main'
expect_deny  'ssh prod bash -s < .github/scripts/deploy-remote.sh'
expect_allow 'git push -u origin feat/leaner-claude-md'
expect_allow 'git fetch origin main'
expect_allow 'git log origin/main --oneline'
expect_allow './scripts/merge-release.sh 42'
expect_allow 'gh run list --workflow deploy-prod.yml'
expect_allow 'bash -n .github/scripts/deploy-remote.sh'

echo "=== 2. production is read-only"
expect_deny  'psql -h prod-db.internal -U app app_prod -c "update users set x=1"'
expect_allow "PGOPTIONS='-c default_transaction_read_only=on' psql -h prod-db.internal -U app app_prod"
expect_allow 'psql -h localhost -U acme acme_scratch -c "select 1"'

echo "=== 3. never print a secret"
expect_deny  'cat .env'
expect_deny  'cat acme-bff/.env'
expect_deny  'tail -n 50 /opt/acme/secrets/app.env'
expect_deny  'head acme-tf/envs/oci/terraform.tfvars'
expect_deny  'cat acme-tf/envs/oci/terraform.tfstate'
expect_allow 'cat .env.example'
expect_allow 'cat acme-tf/envs/oci/terraform.tfvars.example'
expect_allow "grep -c '^SECRET_KEY=' .env"
expect_allow 'cat README.md'

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
