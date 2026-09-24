#!/usr/bin/env bash
# PostToolUse(Write|Edit). Warns — does not block — about broken relative links
# in a markdown file that was just written.
#
# Warns rather than blocks because a link may legitimately point at a file the
# same piece of work has not created yet.
#
# It does NOT replace the CI check: doc-links.yml runs
# scripts/check-doc-links.sh over the whole tree and is the gate. This is the
# same script on one file, minutes earlier. A documentation restructuring can
# push a handful of broken links to main in one commit, which is what those
# minutes are worth.
set -uo pipefail

f=$(jq -r '.tool_input.file_path // .tool_response.filePath // ""')
case "$f" in *.md) ;; *) exit 0 ;; esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
[ -x scripts/check-doc-links.sh ] || exit 0

if ! out=$(scripts/check-doc-links.sh "$f" 2>&1); then
  jq -nc --arg o "$out" '{systemMessage: ("Broken relative links in the file just written:\n" + $o)}'
fi
exit 0
