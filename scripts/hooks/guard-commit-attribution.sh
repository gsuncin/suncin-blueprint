#!/usr/bin/env bash
# PreToolUse(Bash). Denies a git commit carrying AI attribution.
#
# ORCHESTRATION.md -> Commits forbids it "on any surface". A regex closes the
# door; an instruction only asks.
#
# KNOWN FALSE POSITIVE, and it is deliberate rather than unnoticed. This
# matches the COMMAND TEXT, so a command that merely quotes the forbidden
# trailer -- writing this very file through a heredoc, or grepping the history
# for it -- is denied too. Narrowing the match to `-m` arguments would let
# through the shape that actually occurs (a trailer in a commit message file),
# so the guard keeps the cheap false positive and pays for it with the
# occasional workaround. If you hit it, write the file with python or split the
# command; do not weaken this.
#
# Pipe-test both directions:
#   printf '%s' '{"tool_input":{"command":"git commit -m xco-authored-by: y"}}' | this  # DENY
#   printf '%s' '{"tool_input":{"command":"git commit -m docs"}}'       | this  # SILENT
set -uo pipefail

cmd=$(jq -r '.tool_input.command // ""')

printf '%s' "$cmd" | grep -q 'git commit'                          || exit 0
printf '%s' "$cmd" | grep -qiE 'co-authored-by|generated with|🤖'  || exit 0

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "AI attribution is forbidden on any surface (ORCHESTRATION.md -> Commits). Drop the attribution trailer and commit again."
  }
}'
