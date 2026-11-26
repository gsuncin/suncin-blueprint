#!/usr/bin/env bash
# Has this exact tree already passed its suite?
#
#   tested-tree.sh record <suite>   PR_HEAD_SHA required; run after the suite
#   tested-tree.sh lookup <suite>   writes skip=true|false to $GITHUB_OUTPUT
#
# WHY THIS EXISTS. A release PR runs the suites on the merge of develop into
# main, and the push to main ran them again on the tree that merge produced,
# ~25 billed minutes a release to learn what was already known (graav-app
# R-2026-10-30-d3df6f). This is what lets the push skip them, and it stands in front of a
# production deploy, so it is allowed to be wrong in one direction only: running
# a suite it could have skipped costs minutes; skipping one it should have run
# ships an untested image.
#
# THE IDENTITY IS THE GIT TREE, NOT THE COMMIT. A release PR is tested at
# refs/pull/N/merge and shipped as a different merge commit, so no sha is shared
# between them. Their trees are equal exactly when main did not move under the
# PR, and a tree hash covers every file, workflows included. So the PR records
# the tree it tested, on its head commit, which is the one commit both sides can
# name: the second parent of the merge.
#
# A commit status and not actions/cache: a PR's cache scope is not readable from
# main. Commit statuses need `statuses: write` on record and `statuses: read` on
# lookup; without the read, every lookup is a 403 and tests run on every push
# with nothing going red, so check-deploy-contract.sh asserts it.
#
# ONLY THE RECORD JOB CAN VOUCH FOR A SUITE. Status-write is held by more than the
# record job, and a status leaves nothing in the tree, so lookup reads the list
# endpoint, the one that says who posted, and requires RECORDER on the NEWEST
# entry for the context. The newest and not any: a forged or failed status posted
# after a good one has to win, or it could be skipped straight over. A miss means
# skip=false, and that is what keeps the paging safe. The list is newest first,
# so the newest entry on the first page is the newest there is, and one that has
# fallen off the page can only run the tests.
#
# lookup exits 0 whatever it finds: every doubtful case is an answer, skip=false,
# which runs the tests. It exits non-zero only on a usage error, which fails the
# gate job, and a failed gate publishes no image at all.
set -uo pipefail

subcommand="${1:-}"
suite="${2:-}"

if ! [[ "$suite" =~ ^[a-z0-9-]+$ ]]; then
    echo "::error::usage: tested-tree.sh record|lookup <suite>" >&2
    exit 2
fi

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set (owner/repo)}"
context="tested-tree/${suite}"

# Who a status posted with GITHUB_TOKEN says it came from: read off a live
# /commits/<sha>/statuses response on 2026-10-30, creator.login with type Bot.
RECORDER='github-actions[bot]'

case "$subcommand" in
record)
    : "${PR_HEAD_SHA:?PR_HEAD_SHA must be set: the status goes on the PR head, the commit main can name}"
    tree="$(git rev-parse 'HEAD^{tree}')" || exit 1
    if ! gh api -X POST "repos/${GITHUB_REPOSITORY}/statuses/${PR_HEAD_SHA}" \
        -f state=success -f "context=${context}" -f "description=${tree}" > /dev/null; then
        echo "::warning::could not record ${context} on ${PR_HEAD_SHA}; the push to main will run the suite again" >&2
        exit 1
    fi
    echo "recorded ${context} on ${PR_HEAD_SHA}: tree ${tree}"
    ;;

lookup)
    # Runs the tests and says why. A skip is the only answer that needs proof.
    run_the_tests() {
        echo "run the tests (${suite}): $1"
        echo "skip=false" >> "$GITHUB_OUTPUT"
        exit 0
    }
    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

    [ "${GITHUB_EVENT_NAME:-}" = push ] \
        || run_the_tests "event is '${GITHUB_EVENT_NAME:-}', not push"
    [ "${GITHUB_REF:-}" = refs/heads/main ] \
        || run_the_tests "ref is '${GITHUB_REF:-}', not refs/heads/main"

    # A squash, a rebase or a fast-forward has no second parent, so no PR head
    # to read. fetch-depth 2 brings both parents of a merge.
    pr_head="$(git rev-parse --verify --quiet 'HEAD^2^{commit}')" \
        || run_the_tests "HEAD has no second parent"
    tree="$(git rev-parse --verify --quiet 'HEAD^{tree}')" \
        || run_the_tests "could not read HEAD's tree"

    # Not the combined /status endpoint, which has no creator. per_page=100, the
    # most it gives, so the default page of 30 is not what a busy commit is
    # judged on; the header says why one page is enough.
    answer="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${pr_head}/statuses?per_page=100")" \
        || run_the_tests "the status API failed for ${pr_head}"
    newest="$(jq -r --arg context "$context" \
        'first(.[] | select(.context == $context))
         | "\(.state) \(.creator.login // "nobody") \(.description // "")"' \
        <<< "$answer" 2> /dev/null)" \
        || run_the_tests "the status API answered something unreadable for ${pr_head}"
    [ -n "$newest" ] \
        || run_the_tests "no ${context} in the newest statuses of ${pr_head}"
    read -r state author recorded <<< "$newest"

    [ "$state" = success ] \
        || run_the_tests "the newest ${context} on ${pr_head} is '${state}'"
    [ "$author" = "$RECORDER" ] \
        || run_the_tests "the newest ${context} on ${pr_head} came from '${author}', not ${RECORDER}"
    [ "$recorded" = "$tree" ] \
        || run_the_tests "${pr_head} tested tree ${recorded}, but HEAD is ${tree}"

    echo "skip the tests (${suite}): ${pr_head} passed tree ${tree}, which is exactly HEAD"
    echo "skip=true" >> "$GITHUB_OUTPUT"
    ;;

*)
    echo "::error::usage: tested-tree.sh record|lookup <suite>" >&2
    exit 2
    ;;
esac
