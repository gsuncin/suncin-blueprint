#!/usr/bin/env bash
# Tests for scripts/merge-release.sh. No token, no network, a few seconds.
#
# Why these exist (specs 488a9ee4, D-4): five release PRs in November 2026 were
# merged in the minute they were opened. The push to main then found no
# tested-tree status and ran both suites again, ~410 billed minutes. The script
# waits for the checks first, and these cases pin the ways it must refuse:
# a failed check, a head that moved, an open review thread, a PR not into main.
#
# The seam is a `gh` shim on PATH. `pr view` answers from view.json (or
# view.<n>.json for its n-th call), `pr checks` answers checks.<n>.json for its
# n-th call and repeats the last one, `pr ready` and `pr merge` are logged.
# An unrecognised call fails loudly, never with an empty answer.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/merge-release.sh"

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is not installed, and the script needs it."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
ok() { printf '    ok   %s\n' "$1"; passed=$((passed + 1)); }
no() { printf '    FAIL %s\n' "$1"; failed=$((failed + 1)); }
case_header() { printf '\n=== %s\n' "$1"; }

SHA=1111111111111111111111111111111111111111

new_sandbox() {
    D="$WORK/$1"
    mkdir -p "$D/bin"
    : >"$D/gh.log"
    cat >"$D/bin/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >>"$GH_STATE/gh.log"
next() {  # next <prefix>: the n-th answer for this prefix, the last one repeated
    local n f
    n=$(( $(cat "$GH_STATE/$1.count" 2>/dev/null || echo 0) + 1 ))
    echo "$n" >"$GH_STATE/$1.count"
    f="$GH_STATE/$1.$n.json"
    while [ ! -f "$f" ] && [ "$n" -gt 1 ]; do n=$((n - 1)); f="$GH_STATE/$1.$n.json"; done
    [ -f "$f" ] || f="$GH_STATE/$1.json"
    [ -f "$f" ] || { echo "shim: no $1 answer" >&2; exit 97; }
    cat "$f"
}
case "$1 $2" in
    "pr view")   next view ;;
    "pr checks") if [ -f "$GH_STATE/checks.none" ]; then echo "no checks reported on the 'develop' branch" >&2; exit 1; fi
                 next checks ;;
    "pr ready")  echo "marked ready" ;;
    "pr merge")  echo "merged" ;;
    *) echo "shim: unexpected gh $*" >&2; exit 98 ;;
esac
SHIM
    chmod +x "$D/bin/gh"
    # The review gate is a seam too: its own behaviour is pr-review-gate.sh's.
    printf '#!/usr/bin/env bash\necho "gate $*" >>"%s/gh.log"\nexit %s\n' "$D" "${GATE_EXIT:-0}" >"$D/gate"
    chmod +x "$D/gate"
    view '{"baseRefName":"main","state":"OPEN","isDraft":false,"headRefOid":"'$SHA'"}'
}
view()   { printf '%s\n' "$1" >"$D/view.json"; }
checks() { printf '%s\n' "$2" >"$D/checks.$1.json"; }

run() {
    OUT="$(PATH="$D/bin:$PATH" GH_STATE="$D" REVIEW_GATE="$D/gate" \
        MERGE_RELEASE_INTERVAL=0 MERGE_RELEASE_TIMEOUT="${TIMEOUT:-5}" \
        "$SCRIPT" "$@" 2>&1)"
    STATUS=$?
}
merged() { grep -q '^pr merge' "$D/gh.log"; }

PASS='[{"name":"tests / django","bucket":"pass"},{"name":"gate","bucket":"pass"}]'

case_header "waits while a check is pending, then reports without merging"
new_sandbox pending
checks 1 '[{"name":"tests / django","bucket":"pending"}]'
checks 2 '[{"name":"tests / django","bucket":"pending"}]'
checks 3 "$PASS"
run 42
[ "$STATUS" -eq 0 ] && ok "exit 0" || no "exit $STATUS: $OUT"
[ "$(cat "$D/checks.count")" -ge 3 ] && ok "polled until nothing was pending" || no "polled $(cat "$D/checks.count") times"
merged && no "merged without --merge" || ok "no merge without --merge"
grep -q "gate 42" "$D/gh.log" && ok "ran the review gate" || no "review gate not run"
grep -q -- "--match-head-commit $SHA" <<<"$OUT" && ok "prints the merge command pinned to the head" || no "no pinned command in: $OUT"

case_header "--merge merges the head the checks ran on"
new_sandbox merge
checks 1 "$PASS"
run 42 --merge
[ "$STATUS" -eq 0 ] && ok "exit 0" || no "exit $STATUS: $OUT"
grep -q "^pr merge 42 --merge --match-head-commit $SHA" "$D/gh.log" && ok "merge commit, pinned to $SHA" || no "merge call: $(grep '^pr merge' "$D/gh.log")"

case_header "a draft is marked ready before waiting"
new_sandbox draft
view '{"baseRefName":"main","state":"OPEN","isDraft":true,"headRefOid":"'$SHA'"}'
checks 1 "$PASS"
run 42
grep -q '^pr ready 42' "$D/gh.log" && ok "pr ready called" || no "pr ready not called"
[ "$STATUS" -eq 0 ] && ok "exit 0" || no "exit $STATUS: $OUT"

case_header "a failed check refuses the merge"
new_sandbox failed
checks 1 '[{"name":"tests / django","bucket":"fail"},{"name":"gate","bucket":"pass"}]'
run 42 --merge
[ "$STATUS" -ne 0 ] && ok "exit non-zero" || no "exit 0 with a failed check"
merged && no "merged over a failed check" || ok "not merged"
grep -q "tests / django" <<<"$OUT" && ok "names the failed check" || no "does not name it: $OUT"

case_header "a cancelled check refuses the merge"
new_sandbox cancelled
checks 1 '[{"name":"tests / vitest-and-playwright","bucket":"cancel"}]'
run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS, merged=$(merged && echo yes || echo no)"

case_header "--allow-failing lets one named check be red, and only that one"
new_sandbox allowed
checks 1 '[{"name":"sync-check","bucket":"fail"},{"name":"tests / django","bucket":"pass"}]'
run 42 --merge --allow-failing sync-check
[ "$STATUS" -eq 0 ] && merged && ok "merged with sync-check allowed" || no "exit $STATUS: $OUT"
new_sandbox allowed-other
checks 1 '[{"name":"sync-check","bucket":"fail"},{"name":"tests / django","bucket":"fail"}]'
run 42 --merge --allow-failing sync-check
[ "$STATUS" -ne 0 ] && ! merged && ok "another red check still refuses" || no "exit $STATUS: $OUT"

case_header "a head that moved while waiting refuses the merge"
new_sandbox moved
printf '%s\n' '{"baseRefName":"main","state":"OPEN","isDraft":false,"headRefOid":"'$SHA'"}' >"$D/view.1.json"
printf '%s\n' '{"baseRefName":"main","state":"OPEN","isDraft":false,"headRefOid":"2222222222222222222222222222222222222222"}' >"$D/view.2.json"
checks 1 "$PASS"
run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS: $OUT"

case_header "a failing review gate refuses the merge"
GATE_EXIT=1 new_sandbox gate-red
checks 1 "$PASS"
run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS: $OUT"

case_header "a PR that is not into main is refused before anything else"
new_sandbox base
view '{"baseRefName":"develop","state":"OPEN","isDraft":true,"headRefOid":"'$SHA'"}'
run 42 --merge
[ "$STATUS" -ne 0 ] && ok "refused" || no "exit 0 on a PR into develop"
grep -qE '^pr (ready|checks|merge)' "$D/gh.log" && no "acted on it: $(cat "$D/gh.log")" || ok "touched nothing"

case_header "a closed PR is refused"
new_sandbox closed
view '{"baseRefName":"main","state":"MERGED","isDraft":false,"headRefOid":"'$SHA'"}'
run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS"

case_header "no check ever reported: times out instead of merging"
new_sandbox none
touch "$D/checks.none"
TIMEOUT=0 run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS: $OUT"

case_header "an empty check list is not a green one"
new_sandbox empty
checks 1 '[]'
TIMEOUT=0 run 42 --merge
[ "$STATUS" -ne 0 ] && ! merged && ok "refused" || no "exit $STATUS: $OUT"

case_header "usage"
new_sandbox usage
run
[ "$STATUS" -ne 0 ] && ok "no PR number is an error" || no "exit 0 with no arguments"
run 42 --bogus
[ "$STATUS" -ne 0 ] && ! merged && ok "an unknown flag is an error" || no "exit $STATUS"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
