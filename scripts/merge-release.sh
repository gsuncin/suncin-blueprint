#!/usr/bin/env bash
# Wait for a release PR's checks, then merge it into main, or say exactly how.
#
# WHY (graav-app PR #504). The push to main skips both suites when the PR has
# already recorded that exact tree as tested (tested-tree.sh). Five graav-app
# release PRs in November 2026 were merged in the minute they were opened, before the PR
# run could record anything, so the push ran both suites again: ~410 billed
# minutes. Waiting here costs no minutes at all.
#
# What it does, in order, and it stops at the first refusal:
#   1. the PR must be OPEN and into main;
#   2. a draft is marked ready, which is what starts its checks;
#   3. it waits until at least one check exists and none is pending;
#   4. any failed or cancelled check refuses, unless named by --allow-failing
#      (for a check known to be red for a reason that is not a test);
#   5. the head must still be the one the checks ran on;
#   6. scripts/pr-review-gate.sh must pass;
#   7. with --merge it merges as a merge commit, pinned to that head with
#      --match-head-commit. Without it, it prints that command.
#
# The merge to main deploys production (specs/RELEASES.md), so it stays a step a
# person decides: this runs the merge, it does not choose to.
#
# Usage: ./scripts/merge-release.sh <pr> [--merge] [--allow-failing <check>]...
#   MERGE_RELEASE_INTERVAL  seconds between polls (default 30)
#   MERGE_RELEASE_TIMEOUT   seconds before giving up (default 5400)
set -euo pipefail

usage() { echo "usage: merge-release.sh <pr> [--merge] [--allow-failing <check>]..." >&2; exit 2; }
fail() { echo "REFUSED: $*" >&2; exit 1; }

PR="${1:-}"
[[ "$PR" =~ ^[0-9]+$ ]] || usage
shift

do_merge=0
allowed='[]'
while [ $# -gt 0 ]; do
    case "$1" in
        --merge) do_merge=1 ;;
        --allow-failing)
            [ $# -ge 2 ] || usage
            allowed="$(jq -c --arg n "$2" '. + [$n]' <<<"$allowed")"
            shift ;;
        *) usage ;;
    esac
    shift
done

interval="${MERGE_RELEASE_INTERVAL:-30}"
timeout="${MERGE_RELEASE_TIMEOUT:-5400}"
gate="${REVIEW_GATE:-$(cd "$(dirname "$0")" && pwd)/pr-review-gate.sh}"

view() { gh pr view "$PR" --json baseRefName,state,isDraft,headRefOid; }

info="$(view)"
[ "$(jq -r .state <<<"$info")" = OPEN ] || fail "#$PR is $(jq -r .state <<<"$info"), not OPEN"
[ "$(jq -r .baseRefName <<<"$info")" = main ] \
    || fail "#$PR targets $(jq -r .baseRefName <<<"$info"); this is for release PRs into main"
head="$(jq -r .headRefOid <<<"$info")"

if [ "$(jq -r .isDraft <<<"$info")" = true ]; then
    echo "#$PR is a draft: marking it ready, which starts its checks"
    gh pr ready "$PR"
fi

# `gh pr checks` errors with "no checks reported" before the first one
# registers, which is the normal state for a few seconds after `ready`. That,
# an empty list and anything unparsable all read as "nothing yet", never green.
start=$SECONDS
while :; do
    checks="$(gh pr checks "$PR" --json name,bucket 2>/dev/null || true)"
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$checks" || checks='[]'
    total="$(jq length <<<"$checks")"
    pending="$(jq '[.[] | select(.bucket == "pending")] | length' <<<"$checks")"
    if [ "$total" -gt 0 ] && [ "$pending" -eq 0 ]; then break; fi
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
        fail "after ${timeout}s, $total check(s) reported and $pending still pending"
    fi
    echo "waiting: $total check(s), $pending pending"
    sleep "$interval"
done

red="$(jq -r --argjson ok "$allowed" '
    .[] | select(.bucket == "fail" or .bucket == "cancel")
        | select(.name as $n | $ok | index($n) | not)
        | "  \(.bucket)  \(.name)"' <<<"$checks")"
tolerated="$(jq -r --argjson ok "$allowed" '
    .[] | select(.bucket == "fail" or .bucket == "cancel")
        | select(.name as $n | $ok | index($n)) | "  \(.bucket)  \(.name) (allowed)"' <<<"$checks")"
[ -z "$tolerated" ] || printf '%s\n' "$tolerated"
[ -z "$red" ] || fail "checks did not pass on #$PR:
$red"
echo "checks: $(jq length <<<"$checks") done, none red"

now="$(jq -r .headRefOid <<<"$(view)")"
[ "$now" = "$head" ] || fail "#$PR moved from $head to $now while waiting; run this again"

"$gate" "$PR" || fail "the review gate did not pass on #$PR"

cmd=(gh pr merge "$PR" --merge --match-head-commit "$head")
if [ "$do_merge" -eq 1 ]; then
    "${cmd[@]}"
    echo "merged #$PR at $head"
else
    echo "ready to merge. This deploys production:"
    echo "  ${cmd[*]}"
fi
