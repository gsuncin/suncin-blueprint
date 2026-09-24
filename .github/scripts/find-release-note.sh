#!/usr/bin/env bash
# Resolve a release tag to the one note in releases/ it names.
#
#   find-release-note.sh <tag> [releases-dir]     (default: releases)
#
# Prints `path=<file>` and `title=<its H1, without the #>` on stdout, in the
# shape $GITHUB_OUTPUT takes. Exits 1, saying why, on anything else.
#
# Two identifier formats, both valid forever (specs/RELEASES.md):
#
#   R-NNN                 the sequential notes, R-001 onward. Retired: a number
#                         read at write time is claimed at merge time, and
#                         nothing reserves it in between, so two branches in
#                         flight pick the same one.
#   R-YYYY-MM-DD-xxxxxx   the date the note was written + 6 lowercase hex.
#
# The workflow's tag trigger is deliberately WIDER than the second format, and
# this is where it gets narrow: a tag the trigger misses produces no run at all
# — a release that silently never publishes — while a tag refused here is a
# red run somebody sees.
#
# Fails closed. Zero matches means the tag was pushed before its note; two means
# one identifier was used twice, and publishing either one would be wrong. That
# second case is exactly what an `R-NNN` collision looks like on disk: two
# different filenames, so git merged them without a conflict.
set -euo pipefail

tag="${1:-}"
dir="${2:-releases}"

old='^R-[0-9]{3}$'
new='^R-20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])-[0-9a-f]{6}$'
if ! [[ "$tag" =~ $old || "$tag" =~ $new ]]; then
  echo "'${tag}' is not a release identifier: expected R-NNN or R-YYYY-MM-DD-xxxxxx (6 lowercase hex)." >&2
  exit 1
fi

# The tag is validated above, so it carries no glob characters of its own; the
# only wildcard here is the slug's.
shopt -s nullglob
matches=("${dir}/${tag}"-*.md)
shopt -u nullglob

if [ "${#matches[@]}" -eq 0 ]; then
  echo "No note for ${tag}: nothing matches ${dir}/${tag}-*.md — write the note before tagging." >&2
  exit 1
fi
if [ "${#matches[@]}" -ne 1 ]; then
  echo "Expected exactly one note for ${tag}, found ${#matches[@]}:" >&2
  printf '  %s\n' "${matches[@]}" >&2
  exit 1
fi

echo "path=${matches[0]}"
echo "title=$(head -1 "${matches[0]}" | sed -E 's/^#+ *//')"
