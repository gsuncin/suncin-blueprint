#!/usr/bin/env bash
# Fails if a PR has unresolved review threads or a standing CHANGES_REQUESTED.
#
# Review comments are a merge gate (specs/RELEASES.md). Inline review threads do
# NOT appear in `gh pr view --comments`, which is why this queries GraphQL.
#
# Usage: ./scripts/pr-review-gate.sh <pr-number>
set -euo pipefail

PR="${1:?usage: pr-review-gate.sh <pr-number>}"
read -r OWNER REPO <<<"$(gh repo view --json owner,name \
    --jq '"\(.owner.login) \(.name)"')"

result="$(gh api graphql \
    -f query='
    query($owner:String!, $repo:String!, $pr:Int!) {
      repository(owner:$owner, name:$repo) {
        pullRequest(number:$pr) {
          reviewThreads(first:100) {
            totalCount
            nodes {
              id isResolved isOutdated path line
              comments(first:1) { nodes { author { login } body url } }
            }
          }
          reviews(last:30) { nodes { state author { login } } }
        }
      }
    }' \
    -F owner="$OWNER" -F repo="$REPO" -F pr="$PR")"

total="$(jq -r '.data.repository.pullRequest.reviewThreads.totalCount' <<<"$result")"
[ "$total" -ge 100 ] && echo "WARNING: $total threads; only the first 100 were fetched."

unresolved="$(jq -r '
    .data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved == false)
    | "\(.path):\(.line // "?") @\(.comments.nodes[0].author.login) "
      + (.comments.nodes[0].body | gsub("\n"; " ") | .[0:120])
      + "\n    thread:\(.id)\n    \(.comments.nodes[0].url)"
' <<<"$result")"

# A CHANGES_REQUESTED review stands until the same author approves or dismisses.
blocking="$(jq -r '
    [ .data.repository.pullRequest.reviews.nodes[]
      | select(.state == "CHANGES_REQUESTED") | .author.login ] | unique | .[]
' <<<"$result")"

fail=0
if [ -n "$unresolved" ]; then
    echo "Unresolved review threads:"; echo "$unresolved"; echo; fail=1
fi
if [ -n "$blocking" ]; then
    echo "Standing CHANGES_REQUESTED from: $blocking"; echo; fail=1
fi

if [ "$fail" -eq 1 ]; then
    cat <<'MSG'
Each thread gets exactly one of two outcomes (specs/RELEASES.md):
  - Accept: change the code, push, reply linking the commit, then resolve.
  - Resolve without change: reply with the reason, pointing at code or a spec,
    then resolve.
The reply is what makes it legitimate. A resolved thread with no answer
destroys the reason for the decision.
MSG
    exit 1
fi

echo "No unresolved review threads on #$PR."
