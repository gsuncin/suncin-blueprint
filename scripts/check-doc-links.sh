#!/usr/bin/env bash
# Verifies every relative markdown link inside specs/, history/, releases/ and
# CLAUDE.md points at a file that exists. Fails closed: if it finds zero links
# to check, that is a bug in the script, not a clean bill of health.
#
# With file arguments it checks only those files, using the SAME extraction —
# one rule, not two that drift. That mode is what the PostToolUse hook in
# .claude/settings.json calls after a markdown edit, so a broken link is seen
# seconds after it is written rather than on the PR. It does NOT fail on zero
# links, because one file legitimately may have none.
set -euo pipefail
cd "$(dirname "$0")/.."

broken=0
checked=0

# `history/` only exists once the specs restructuring is adopted, so it is
# included when present rather than assumed. Everything else is required: a
# target that has gone missing narrows the sweep silently, which is the same
# failure as checking nothing and reporting green.
targets=("specs/" "releases/" "CLAUDE.md")
[ -d history ] && targets+=("history/")
single_file=0
if [ "$#" -gt 0 ]; then
  single_file=1
  targets=()
  for arg in "$@"; do
    # A hook hands us an absolute path; grep -rn must print the same prefix the
    # link is resolved against, so make it repo-relative first.
    targets+=("${arg#"$PWD/"}")
  done
fi

while IFS=: read -r file line link; do
  # strip a #anchor suffix before checking the file exists
  target="${link%%#*}"
  [ -z "$target" ] && continue  # pure #anchor link, same file
  dir="$(dirname "$file")"
  resolved="$dir/$target"
  checked=$((checked + 1))
  if [ ! -e "$resolved" ]; then
    echo "BROKEN: $file:$line -> $link (resolved: $resolved)"
    broken=$((broken + 1))
  fi
done < <(
  grep -rnoE '\]\([^)http][^)]*\)' "${targets[@]}" 2>/dev/null \
    | sed -E 's/^([^:]+):([0-9]+):\]\((.*)\)$/\1:\2:\3/'
)

if [ "$single_file" -eq 0 ]; then
  echo "Checked $checked relative links."
  if [ "$checked" -eq 0 ]; then
    echo "FAIL: zero links found — the check itself is broken, not the docs."
    exit 1
  fi
fi
if [ "$broken" -gt 0 ]; then
  echo "FAIL: $broken broken link(s)."
  exit 1
fi
[ "$single_file" -eq 1 ] && exit 0
echo "OK: zero broken links."
