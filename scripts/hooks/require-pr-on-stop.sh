#!/usr/bin/env bash
# Stop. Blocks ONCE when committed work has no pull request into the
# integration branch.
#
# Work lands on `staging` and `staging` merges to `main` a release at a time
# (RELEASES.md, the two-branch flow). Both halves are easy to get right when
# someone remembers and easy to get wrong when nobody does, so this checks
# instead of trusting: a branch with commits on it and no PR is work that has
# nowhere to land, and a PR opened straight against `main` skips the release
# gate.
#
# THE BASE IS DETECTED, NOT ASSUMED. A repository that has not adopted the
# two-branch flow has no `origin/staging`, and a hook that demanded one would
# block every stop in it forever. So: `staging` if it exists, otherwise the
# remote's own default branch.
#
# Fires only when there is something to propose -- commits ahead of the base --
# and only on a clean tree, because a dirty one belongs to
# warn-uncommitted-on-stop.sh and that hook should speak first.
#
# Self-terminating, like its sibling: open the PR, stop again, a PR exists,
# the hook is silent.
#
# Two deliberate caveats, both in the reason text so the model can answer them:
#   - A hook cannot tell a finished workstream from a question answered on the
#     same branch. Mid-flight work is a legitimate "not yet".
#   - `gh` failing offline or unauthenticated is indistinguishable here from
#     "no PR exists", so the reason allows saying so rather than inventing one.
set -uo pipefail

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

# NOT $CLAUDE_PROJECT_DIR: that stays pinned to the directory the session
# started in and does not follow an agent into its worktree, so it would have
# us reading the main checkout's branch while the work sits somewhere else.
# The `cwd` field does follow.
cd "$(printf '%s' "$input" | jq -r '.cwd // empty')" 2>/dev/null ||
  cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

branch=$(git branch --show-current 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0

if git rev-parse --verify --quiet origin/staging >/dev/null 2>&1; then
  base_branch=staging
else
  base_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  base_branch=${base_branch#origin/}
  [ -n "$base_branch" ] || base_branch=main
  git rev-parse --verify --quiet "origin/$base_branch" >/dev/null 2>&1 || exit 0
fi

# The integration branches themselves are never the subject of a feature PR.
case "$branch" in staging | main | "$base_branch") exit 0 ;; esac

ahead=$(git rev-list --count "origin/$base_branch..$branch" 2>/dev/null || echo 0)
[ "${ahead:-0}" -gt 0 ] || exit 0

[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0

command -v gh >/dev/null 2>&1 || exit 0
base=$(gh pr view "$branch" --json baseRefName -q .baseRefName 2>/dev/null) || base=""

if [ -z "$base" ]; then
  REASON="\`$branch\` has $ahead commit(s) ahead of \`origin/$base_branch\` and no open pull request. Work that is finished gets a PR into \`$base_branch\` -- \`gh pr create --base $base_branch\` -- with what changed, what was deliberately left out, and why (flow step 9). If the work is NOT finished, or \`gh\` cannot reach GitHub from here, say which and stop."
elif [ "$base" != "$base_branch" ]; then
  REASON="The open PR for \`$branch\` targets \`$base\`, not \`$base_branch\`. Work lands on \`$base_branch\` -- RELEASES.md, the two-branch flow. Retarget it with \`gh pr edit --base $base_branch\`, or say why this one is the exception and stop."
else
  exit 0
fi

jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
