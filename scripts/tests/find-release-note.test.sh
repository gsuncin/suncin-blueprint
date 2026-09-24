#!/usr/bin/env bash
# Tests for .github/scripts/find-release-note.sh and for the tag trigger in
# .github/workflows/release-notes.yml. No token, no network, well under a
# second.
#
# Why these exist (workstream e85445e8, GitHub #131, T-2): the
# release identifier gained a second format — `R-YYYY-MM-DD-<6 hex>` beside the
# old `R-NNN`, which stays valid forever (D-3). The dangerous half is the
# trigger. A tag that matches no `on.push.tags` pattern produces NO run at all,
# not a failing one, so a wrong pattern is a release that silently never
# publishes. Nothing downstream can see that; only a check that reads the
# patterns out of the workflow and holds real tags against them can.
#
# The patterns are read from the workflow file, not restated here, and the
# note set is read from the real releases/ directory, not listed — both fail
# closed when the derivation comes back empty, because a loop over nothing is
# a pass that checked nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/find-release-note.sh"
WORKFLOW="$ROOT/.github/workflows/release-notes.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
OUT=""
STATUS=0

ok() {
  printf '    ok   %s\n' "$1"
  passed=$((passed + 1))
}
no() {
  printf '    FAIL %s\n' "$1"
  failed=$((failed + 1))
}
case_header() { printf '\n  %s\n' "$1"; }

expect_status() {
  if [ "$STATUS" -eq "$1" ]; then ok "exit $STATUS"; else no "expected exit $1, got $STATUS"; fi
}
expect_says() {
  if printf '%s' "$OUT" | grep -qF -- "$1"; then ok "says \"$1\""; else no "expected output to contain \"$1\" — got: $OUT"; fi
}

# find <tag> <releases dir>
find_note() {
  if [ ! -x "$SCRIPT" ]; then
    OUT="missing or not executable: $SCRIPT"
    STATUS=127
    return
  fi
  OUT="$("$SCRIPT" "$1" "$2" 2>&1)"
  STATUS=$?
}

fixture() {
  local d="$WORK/$1"
  mkdir -p "$d"
  shift
  local f
  for f in "$@"; do
    printf '# %s — a title with `backticks` in it\n\nbody\n' "${f%%-[a-z]*}" >"$d/$f"
  done
  echo "$d"
}

# ---------------------------------------------------------------------------
printf 'find-release-note.sh\n'

case_header "an old R-NNN tag resolves to its note"
d="$(fixture old R-064-the-dragged-card.md R-065-something-else.md TEMPLATE.md)"
find_note R-064 "$d"
expect_status 0
expect_says "path=$d/R-064-the-dragged-card.md"
expect_says 'title=R-064 — a title with `backticks` in it'

case_header "a new R-YYYY-MM-DD-xxxxxx tag resolves to its note"
d="$(fixture new R-064-the-dragged-card.md R-2026-09-23-a3f9c1-the-new-shape.md R-2026-09-23-0b7e22-same-day-other-note.md)"
find_note R-2026-09-23-a3f9c1 "$d"
expect_status 0
expect_says "path=$d/R-2026-09-23-a3f9c1-the-new-shape.md"

case_header "a tag with no note fails closed"
d="$(fixture missing R-064-the-dragged-card.md)"
find_note R-2026-09-23-ffffff "$d"
expect_status 1
expect_says "No note for R-2026-09-23-ffffff"

case_header "an empty releases directory fails closed"
d="$WORK/empty"
mkdir -p "$d"
find_note R-064 "$d"
expect_status 1
expect_says "No note for R-064"

case_header "a releases directory that does not exist fails closed"
find_note R-064 "$WORK/nowhere"
expect_status 1

case_header "two notes carrying one id is refused, not published"
d="$(fixture dup R-064-the-dragged-card.md R-064-legacy-storage-command-defects.md)"
find_note R-064 "$d"
expect_status 1
expect_says "Expected exactly one note for R-064, found 2"

case_header "an old three-digit tag does not match a new-format note by prefix"
d="$(fixture prefix R-2026-09-23-a3f9c1-the-new-shape.md)"
find_note R-202 "$d"
expect_status 1

for bad in 'R-2026-09-23-foo' 'R-2026-13-01-a3f9c1' 'R-2026-09-23-A3F9C1' 'R-64' 'R-0640' 'v1.2.3' 'R-*' 'R-2026-09-23-a3f9c1-extra' ''; do
  case_header "a malformed tag is refused: '$bad'"
  d="$(fixture "bad$passed$failed" R-064-the-dragged-card.md R-2026-09-23-a3f9c1-the-new-shape.md)"
  find_note "$bad" "$d"
  expect_status 1
  expect_says "not a release identifier"
done

# ---------------------------------------------------------------------------
printf '\nrelease-notes.yml trigger\n'

# The `tags:` list, read out of the workflow. GitHub's filter glob and bash's
# `[[ == ]]` agree on everything these patterns use (literals, `[0-9]`, `*`);
# they differ on `/`, which no tag here contains, and on `?` and `+`, which the
# test refuses outright so a pattern using them cannot pass by accident.
patterns=()
while IFS= read -r p; do
  [ -n "$p" ] && patterns+=("$p")
done < <(sed -n 's/^[[:space:]]*tags:[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' "$WORKFLOW" | tr ',' '\n' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

case_header "the trigger has patterns at all"
if [ "${#patterns[@]}" -ge 2 ]; then ok "${#patterns[@]} patterns: ${patterns[*]}"; else no "expected both formats in on.push.tags, read ${#patterns[@]}: ${patterns[*]:-}"; fi
for p in ${patterns[@]+"${patterns[@]}"}; do
  case "$p" in
    *'?'* | *'+'* | *'!'*) no "pattern '$p' uses GitHub glob syntax bash reads differently" ;;
  esac
done

triggers() {
  local tag="$1" p
  for p in ${patterns[@]+"${patterns[@]}"}; do
    # shellcheck disable=SC2053 # the pattern is meant to be a glob
    [[ "$tag" == $p ]] && return 0
  done
  return 1
}

for tag in R-001 R-064 R-082 R-2026-09-23-a3f9c1 R-2031-01-02-000000; do
  case_header "tag $tag triggers a run"
  if triggers "$tag"; then ok "matched"; else no "no pattern matches $tag — it would publish nothing, silently"; fi
done
for tag in v1.2.3 main R-0640x; do
  case_header "tag $tag does not trigger a run"
  if triggers "$tag"; then no "$tag matched a release pattern"; else ok "not matched"; fi
done

# ---------------------------------------------------------------------------
printf '\nevery note in releases/\n'

# Derived from the directory, not listed. Each note's identifier must trigger
# the workflow AND resolve back to exactly that file — the round trip a real
# tag push makes.
notes=0
for f in "$ROOT"/releases/R-*.md; do
  [ -e "$f" ] || continue
  notes=$((notes + 1))
  name="$(basename "$f")"
  if [[ "$name" =~ ^(R-20[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9a-f]{6})-.+\.md$ ]] ||
     [[ "$name" =~ ^(R-[0-9]{3})-.+\.md$ ]]; then
    id="${BASH_REMATCH[1]}"
  else
    no "$name is in neither release-identifier format"
    continue
  fi
  triggers "$id" || no "$id ($name) matches no trigger pattern"
  find_note "$id" "$ROOT/releases"
  if [ "$STATUS" -ne 0 ] || ! printf '%s' "$OUT" | grep -qxF "path=$f"; then
    no "$id does not resolve to $name: $OUT"
  fi
done

case_header "the round trip covered the real directory"
if [ "$notes" -gt 0 ]; then ok "$notes notes found and held to the round trip"; else no "zero notes found in releases/ — refusing to call that a pass"; fi

printf '\n%s assertions passed, %s failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
  echo "FAIL: a release tag would not publish the note it names."
  exit 1
fi
if [ "$passed" -eq 0 ]; then
  echo "FAIL: zero assertions ran — the harness is broken, not the script."
  exit 1
fi
echo "OK: both identifier formats trigger the workflow and resolve to their note."
