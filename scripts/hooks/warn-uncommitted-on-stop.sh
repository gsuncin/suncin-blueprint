#!/usr/bin/env bash
# Stop. Blocks ONCE on a dirty working tree.
#
# The rule this enforces exists because uncommitted work dies with the session,
# and it is the rule that most depends on someone remembering. This is
# self-terminating rather than a loop: the model commits, stops again, the tree
# is clean, the hook does not fire. `stop_hook_active` is belt and braces.
#
# Deliberate caveat: if SOMEONE ELSE has uncommitted work in this checkout,
# this complains about something that is not yours. That is what the last
# sentence of the reason is for. Do not commit what you did not write.
set -uo pipefail

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

# NOT $CLAUDE_PROJECT_DIR: it stays pinned to the directory the session started
# in and does not follow an agent into its worktree. Since the writing agents
# carry `isolation: worktree`, reading that variable here would check the main
# checkout every time — nagging about someone else's files while the agent's
# own uncommitted work went unseen, which is the failure this hook exists to
# prevent. The `cwd` field follows Claude; use it.
cd "$(printf '%s' "$input" | jq -r '.cwd // empty')" 2>/dev/null ||
  cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
n=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "${n:-0}" -gt 0 ] || exit 0

REASON="$n file(s) are uncommitted. Commit before you report — a worktree is not storage, and uncommitted work is lost with the session. \`wip(scope):\` is an honest subject line. If this is deliberate — work belonging to someone else in the same checkout, or a scratch file — say so and stop."

jq -nc --arg r "$REASON" '{decision: "block", reason: $r}'
