#!/usr/bin/env bash
# Tests for .github/scripts/retag-unchanged.sh. No token, no network, a few
# seconds.
#
# Why these exist (ported from graav-app R-2026-10-30-d3df6f): the script writes tags production
# pulls. A wrong tag is a service silently rolled back, or an old image under a
# new commit's name, with every check green. So the source of a retag must be
# an ancestor whose paths are provably identical, and when that cannot be shown
# the image stays missing, because a missing image is a skipped deploy and a
# wrong one is an incident.
#
# Seams: `docker` is a shim on PATH backed by a file that plays the registry;
# the sandbox is a real git repository with real merge commits, carrying COPIES
# of the real docker-*.yml and release-images.sh, so the
# derivation is exercised on the files it reads in CI. Nothing test-only exists
# in the script.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/retag-unchanged.sh"

if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git is not installed, and every case here needs it."
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
OUT=""
STATUS=0
D=""

ok() {
  printf '    ok   %s\n' "$1"
  passed=$((passed + 1))
}
no() {
  printf '    FAIL %s\n' "$1"
  failed=$((failed + 1))
}
case_header() { printf '\n=== %s\n' "$1"; }

expect_status() {
  if [ "$STATUS" -eq "$1" ]; then ok "exit $STATUS"; else no "expected exit $1, got $STATUS"; fi
}
expect_says() {
  if printf '%s' "$OUT" | grep -qF -- "$1"; then ok "says \"$1\""; else no "expected output to contain \"$1\""; fi
}

# Derived rather than typed, and it fails closed, for the reason in
# specs/README.md: a loop over nothing is a pass that checked nothing.
# The sandbox has its own two services (acme-svc-documents, acme-svc-intel) so
# the matrix case is exercised with more than one, so the list is read there.
all_repos() { (cd "$D" && .github/scripts/release-images.sh | awk '{ print $2 }' | sort -u); }
ALL_REPOS="$(cd "$ROOT" && .github/scripts/release-images.sh | awk '{ print $2 }' | sort -u)"
if [ -z "$ALL_REPOS" ]; then
  echo "FAIL: release-images.sh listed nothing, so no case below would mean anything."
  exit 1
fi

git_q() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}" >/dev/null 2>&1; }

new_sandbox() {
  D="$WORK/$1"
  mkdir -p "$D/bin" "$D/.github/workflows" "$D/.github/scripts" \
    "$D/acme-bff" "$D/acme-web" "$D/acme-svc-documents/app/deep" "$D/acme-svc-intel/app" \
    "$D/acme-gateway/auth"
  cp "$ROOT"/.github/workflows/docker-*.yml "$D/.github/workflows/"
  cp "$ROOT/.github/scripts/release-images.sh" "$D/.github/scripts/"
  [ -f "$SCRIPT" ] && cp "$SCRIPT" "$D/.github/scripts/"

  echo bff >"$D/acme-bff/manage.py"
  echo web >"$D/acme-web/package.json"
  echo doc >"$D/acme-svc-documents/app/deep/render.py"
  echo intel >"$D/acme-svc-intel/app/score.py"
  echo auth >"$D/acme-gateway/auth/main.py"
  echo compose >"$D/docker-compose.yml"
  echo docs >"$D/README.md"
  : >"$D/registry"
  : >"$D/docker.log"
  printf 'bin\nregistry\ndocker.log\n' >"$D/.gitignore"

  cat >"$D/bin/docker" <<'SHIM'
#!/usr/bin/env bash
# $REGISTRY is the registry, one `repo:tag` per line. An unrecognised call is a
# loud failure, never an empty answer that looks like "not published".
case "${1:-} ${2:-}" in
  "manifest inspect")
    if [ -n "${DENY_REF_MATCHING:-}" ] && printf '%s' "$3" | grep -q "$DENY_REF_MATCHING"; then
      echo "denied: requested access to the resource is denied" >&2
      exit 1
    fi
    if grep -qxF -- "$3" "$REGISTRY"; then
      printf 'inspect %s\n' "$3" >>"$DOCKER_LOG"
      echo '{}'
      exit 0
    fi
    printf 'inspect %s\n' "$3" >>"$DOCKER_LOG"
    echo "no such manifest: $3" >&2
    exit 1
    ;;
  "buildx imagetools")
    [ "${3:-} ${4:-}" = "create -t" ] || { echo "docker shim: unexpected: docker $*" >&2; exit 64; }
    if [ -n "${CREATE_FAILS:-}" ]; then
      echo "ERROR: failed to push" >&2
      exit 1
    fi
    if ! grep -qxF -- "$6" "$REGISTRY"; then
      echo "ERROR: $6: not found" >&2
      exit 1
    fi
    printf 'create %s %s\n' "$5" "$6" >>"$DOCKER_LOG"
    printf '%s\n' "$5" >>"$REGISTRY"
    ;;
  *)
    echo "docker shim: unexpected: docker $*" >&2
    exit 64
    ;;
esac
SHIM
  chmod +x "$D/bin/docker"

  git_q "$D" init -b main
  git_q "$D" add -A
  git_q "$D" commit -m "the tree the box runs"
}

# Adds an entry to docker-web.yml's on.push.paths, which is the first list in
# the file. awk, because BSD sed does not expand \n in a replacement.
add_push_path() {
  awk -v entry="$1" '
    !done && /^ +- "acme-web\/\*\*"/ { print; printf "      - \"%s\"\n", entry; done = 1; next }
    { print }
  ' "$D/.github/workflows/docker-web.yml" >"$D/web.new"
  mv "$D/web.new" "$D/.github/workflows/docker-web.yml"
}

# A real PR: a branch off main, one commit, a merge commit on main.
merge_change_to() {
  local path branch
  branch="pr-$RANDOM-$RANDOM"
  git_q "$D" checkout -b "$branch"
  for path in "$@"; do
    mkdir -p "$D/$(dirname "$path")"
    echo "change $RANDOM" >>"$D/$path"
  done
  git_q "$D" add -A
  git_q "$D" commit -m "change $*"
  git_q "$D" checkout main
  git_q "$D" merge --no-ff -m "Merge pull request from acme/staging" "$branch"
}

sha7() { git -C "$D" rev-parse "${1:-HEAD}" | cut -c1-7; }

publish() {
  # publish <repo> <rev>: the build for that commit finished.
  printf 'ghcr.io/acme/%s:sha-%s\n' "$1" "$(sha7 "$2")" >>"$D/registry"
}
publish_all() {
  local repo
  for repo in $(all_repos); do publish "$repo" "$1"; done
}

# DISPATCH_FILE is where the script lists the builds the workflow must dispatch.
# A case can override it, or empty it with DISPATCH_FILE=.
run_retag() {
  OUT="$(cd "$D" && env PATH="$D/bin:$PATH" REGISTRY="$D/registry" DOCKER_LOG="$D/docker.log" \
    OWNER=Acme DISPATCH_FILE="$D/dispatch" "$@" .github/scripts/retag-unchanged.sh 2>&1)"
  STATUS=$?
  printf '%s\n' "$OUT" | sed 's/^/    | /'
}

expect_retagged() {
  # expect_retagged <repo> <source rev>
  local want
  want="create ghcr.io/acme/$1:sha-$(sha7 HEAD) ghcr.io/acme/$1:sha-$(sha7 "$2")"
  if grep -qxF -- "$want" "$D/docker.log"; then
    ok "$1 retagged from its ancestor"
  else
    no "wanted \`$want\`, the log has: $(grep '^create' "$D/docker.log" | tr '\n' ';')"
  fi
}
expect_left_alone() {
  if grep -q "^create ghcr.io/acme/$1:" "$D/docker.log"; then
    no "$1 was retagged: $(grep "^create ghcr.io/acme/$1:" "$D/docker.log")"
  else
    ok "$1 left alone"
  fi
}
expect_dispatched() {
  # expect_dispatched <workflow basename>...: exactly these, once each, sorted.
  local want got
  want="$(printf '%s\n' "$@")"
  got="$(cat "$D/dispatch" 2>/dev/null)"
  if [ "$got" = "$want" ]; then
    ok "dispatched exactly: $(printf '%s' "$want" | tr '\n' ' ')"
  else
    no "wanted to dispatch [$(printf '%s' "$want" | tr '\n' ' ')], the list has [$(printf '%s' "$got" | tr '\n' ' ')]"
  fi
}
expect_nothing_dispatched() {
  if [ -s "$D/dispatch" ]; then
    no "something was listed for dispatch: $(tr '\n' ' ' <"$D/dispatch")"
  else
    ok "nothing dispatched"
  fi
}
expect_no_tag_written() {
  if grep -q '^create' "$D/docker.log"; then
    no "a tag was written: $(grep '^create' "$D/docker.log" | tr '\n' ';')"
  else
    ok "no tag written"
  fi
}

# --- The ordinary release ---------------------------------------------------
case_header "a bff-only change retags the other four and not bff"
new_sandbox bff-only
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
run_retag
expect_status 0
expect_left_alone acme-bff
expect_retagged acme-web "$base"
expect_retagged acme-svc-documents "$base"
expect_retagged acme-svc-intel "$base"
expect_retagged acme-gateway-auth "$base"

case_header "a docs-only merge does nothing, so nothing deploys"
new_sandbox docs-only
publish_all HEAD
merge_change_to README.md
run_retag
expect_status 0
expect_no_tag_written
expect_says "nothing is built for this commit"

case_header "a merge of many first-parent commits still reads what would build"
new_sandbox two-commit-push
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-web/package.json
merge_change_to README.md
run_retag
expect_status 0
expect_left_alone acme-web
expect_retagged acme-bff "$base"

# --- The svc glob -----------------------------------------------------------
case_header "acme-svc-*/** is one glob shared by both services"
new_sandbox shared-svc-glob
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-svc-intel/app/score.py
run_retag
expect_status 0
expect_left_alone acme-svc-intel
expect_left_alone acme-svc-documents
expect_retagged acme-bff "$base"
expect_retagged acme-web "$base"
expect_retagged acme-gateway-auth "$base"

case_header "the glob reaches a file several directories down"
new_sandbox deep-glob
publish_all HEAD
merge_change_to acme-svc-documents/app/deep/render.py
run_retag
expect_status 0
expect_left_alone acme-svc-documents
expect_left_alone acme-svc-intel

# --- The paths are the workflow's, comments and all --------------------------
# docker-bff.yml's list has comment blocks between its entries, and names files
# outside acme-bff/. A parse that stopped at the first comment would read a
# compose change as "bff unchanged", and retag an image whose build is running.
case_header "a path below a comment in docker-bff.yml's list still counts"
new_sandbox path-after-comment
# The sandbox's docker-bff.yml gains a commented entry, as graav-app's has, so
# the parser is held to a list with comments inside it.
awk '!done && /^ +- "acme-bff\/\*\*"/ { print; print "      # read by a contract test inside acme-bff/"; print "      - \"docker-compose.yml\""; done = 1; next } { print }' \
  "$D/.github/workflows/docker-bff.yml" >"$D/bff.new" && mv "$D/bff.new" "$D/.github/workflows/docker-bff.yml"
git_q "$D" add -A
git_q "$D" commit -m "a commented path entry"
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to docker-compose.yml
run_retag
expect_status 0
expect_left_alone acme-bff
expect_retagged acme-web "$base"

case_header "a change to a build workflow leaves its own image to that build"
new_sandbox workflow-in-its-own-paths
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to .github/workflows/docker-web.yml
run_retag
expect_status 0
expect_left_alone acme-web
expect_retagged acme-bff "$base"

case_header "the paths are read from the workflow, not known in advance"
new_sandbox derived-paths
add_push_path "shared-ui/**"
git_q "$D" add -A
git_q "$D" commit -m "docker-web also watches shared-ui"
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to shared-ui/button.ts
run_retag
expect_status 0
expect_left_alone acme-web
expect_retagged acme-bff "$base"

# --- Walking back -----------------------------------------------------------
# --- What GitHub compares against ---------------------------------------------
# GitHub filters a push against `before`, not against the newest tag. A revert
# makes those two answers differ: the tag walk sees bff identical to an old tag
# while GitHub sees it differ from `before`, and fires its build.
case_header "a revert: release A's bff build went red, R reverts bff alone"
new_sandbox revert-of-a-red-build
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py acme-web/package.json
release_a="$(git -C "$D" rev-parse HEAD)"
# Web published at A, and the three unchanged images were retagged. bff went red.
for repo in acme-web acme-svc-documents acme-svc-intel acme-gateway-auth; do publish "$repo" "$release_a"; done
git_q "$D" checkout -b revert-bff
git_q "$D" checkout "$base" -- acme-bff/manage.py
git_q "$D" commit -m "revert bff"
git_q "$D" checkout main
git_q "$D" merge --no-ff -m "Merge pull request from acme/staging" revert-bff
if git -C "$D" diff --quiet "$base" HEAD -- acme-bff && ! git -C "$D" diff --quiet "$release_a" HEAD -- acme-bff; then
  ok "bff equals the old tag and differs from before, which is the whole case"
else
  no "the fixture is not what this case claims"
fi
run_retag BEFORE="$release_a"
expect_status 0
expect_retagged acme-web "$release_a"
expect_retagged acme-svc-documents "$release_a"
expect_retagged acme-svc-intel "$release_a"
expect_retagged acme-gateway-auth "$release_a"
# Its build fires and owns the tag. Copying the old image here would let the
# deploy run before that build's suite has said anything.
expect_left_alone acme-bff

case_header "a docs-only merge is still nothing with a real before"
new_sandbox docs-only-with-before
publish_all HEAD
before="$(git -C "$D" rev-parse HEAD)"
merge_change_to README.md
run_retag BEFORE="$before"
expect_status 0
expect_no_tag_written

case_header "an ordinary release with a real before reads the same as without one"
new_sandbox bff-only-with-before
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
run_retag BEFORE="$base"
expect_status 0
expect_left_alone acme-bff
expect_retagged acme-web "$base"

case_header "an all-zero before (a new branch) keeps the tag walk's answer"
new_sandbox zero-before
publish_all HEAD
merge_change_to README.md
run_retag BEFORE=0000000000000000000000000000000000000000
expect_status 0
expect_no_tag_written

case_header "an unreachable before (a force-push) keeps the tag walk's answer"
new_sandbox unreachable-before
publish_all HEAD
merge_change_to README.md
run_retag BEFORE=1234567890123456789012345678901234567890
expect_status 0
expect_no_tag_written

case_header "the ancestor is several commits back, past docs merges with no tags"
new_sandbox ancestor-far-back
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to README.md
merge_change_to README.md
merge_change_to README.md
merge_change_to acme-web/package.json
run_retag
expect_status 0
expect_left_alone acme-web
expect_retagged acme-bff "$base"
expect_retagged acme-gateway-auth "$base"

case_header "paths changed since the ancestor leave the image missing"
# bff changed at `broken` and its build went red, so the newest bff tag is
# older than that change. The merge after it touches web. Retagging bff from
# `base` would ship the old bff under the new commit's name and deploy it.
new_sandbox changed-since-ancestor
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
broken="$(git -C "$D" rev-parse HEAD)"
for repo in acme-web acme-svc-documents acme-svc-intel acme-gateway-auth; do publish "$repo" "$broken"; done
merge_change_to acme-web/package.json
run_retag
expect_status 0
expect_left_alone acme-bff
expect_left_alone acme-web
expect_retagged acme-gateway-auth "$broken"

# --- Stranded by a failed build ----------------------------------------------
# 2026-10-31: b18a523 changed acme-gateway/auth and its build never ran (billing),
# so there was no sha-b18a523 for auth. Every later push that did not touch auth
# read "changed since the old tag, so its build owns this tag", and no build had
# been fired by that push to own anything. Production stopped deploying until a
# human dispatched docker-auth.yml. With BEFORE known the two are told apart:
# changed in this push is a build GitHub fired; changed only before it is a build
# that failed, and nobody else will ever run it, so the retag dispatches it.
case_header "an image stranded by a failed build is dispatched, and the rest retagged"
new_sandbox stranded-auth
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-gateway/auth/main.py
broken="$(git -C "$D" rev-parse HEAD)"
# The other four were retagged at `broken`; auth's build failed and wrote nothing.
for repo in acme-bff acme-web acme-svc-documents acme-svc-intel; do publish "$repo" "$broken"; done
merge_change_to README.md
run_retag BEFORE="$broken"
expect_status 0
expect_left_alone acme-gateway-auth
expect_dispatched docker-auth.yml
expect_says "::warning"
expect_says "acme-gateway-auth"
expect_says "sha-$(sha7 "$base")"
expect_retagged acme-bff "$broken"
expect_retagged acme-web "$broken"
expect_retagged acme-svc-documents "$broken"
expect_retagged acme-svc-intel "$broken"

case_header "stranded, and this push fires another build: each is covered once"
new_sandbox stranded-auth-web-push
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-gateway/auth/main.py
broken="$(git -C "$D" rev-parse HEAD)"
for repo in acme-bff acme-web acme-svc-documents acme-svc-intel; do publish "$repo" "$broken"; done
merge_change_to acme-web/package.json
run_retag BEFORE="$broken"
expect_status 0
# GitHub fired web's build; dispatching it too would only cancel that run.
expect_left_alone acme-web
expect_left_alone acme-gateway-auth
expect_dispatched docker-auth.yml
expect_retagged acme-bff "$broken"

case_header "one workflow stranding two images is dispatched once"
new_sandbox stranded-svc
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-svc-intel/app/score.py acme-gateway/auth/main.py
broken="$(git -C "$D" rev-parse HEAD)"
for repo in acme-bff acme-web; do publish "$repo" "$broken"; done
merge_change_to README.md
run_retag BEFORE="$broken"
expect_status 0
expect_left_alone acme-svc-intel
expect_left_alone acme-svc-documents
expect_left_alone acme-gateway-auth
expect_dispatched docker-auth.yml docker-svc.yml
expect_retagged acme-web "$broken"

case_header "without BEFORE a stranded image cannot be told apart: named, not dispatched"
new_sandbox stranded-no-before
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-gateway/auth/main.py
broken="$(git -C "$D" rev-parse HEAD)"
for repo in acme-bff acme-web acme-svc-documents acme-svc-intel; do publish "$repo" "$broken"; done
merge_change_to README.md
run_retag
expect_status 0
expect_left_alone acme-gateway-auth
expect_nothing_dispatched
expect_says "dispatch docker-auth.yml"

case_header "an ordinary release with BEFORE dispatches nothing, whatever an earlier run left"
new_sandbox ordinary-dispatches-nothing
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
echo "docker-web.yml" >"$D/dispatch"
run_retag BEFORE="$base"
expect_status 0
expect_nothing_dispatched
expect_retagged acme-web "$base"

case_header "with nowhere to write the dispatch list, nothing runs"
new_sandbox no-dispatch-file
publish_all HEAD
merge_change_to acme-bff/manage.py
run_retag DISPATCH_FILE=
expect_status 1
expect_says "DISPATCH_FILE"
expect_no_tag_written

case_header "no ancestor has a tag: leave it, and say so"
new_sandbox no-tagged-ancestor
base="$(git -C "$D" rev-parse HEAD)"
publish acme-web "$base"
publish acme-svc-documents "$base"
publish acme-svc-intel "$base"
publish acme-gateway-auth "$base"
merge_change_to acme-web/package.json
run_retag
expect_status 0
expect_left_alone acme-bff
expect_says "::notice"
expect_says "acme-bff"
expect_retagged acme-gateway-auth "$base"

case_header "the walk follows main, never a tag on the merged side of a merge"
# A tag that exists only on the PR side was not on main when anything deployed.
# The side commit comes from an EARLIER merge: the walk starts at HEAD^, so a
# commit on the side of HEAD itself is unreachable however the walk is done, and
# a case built that way passes with --first-parent deleted. It did.
new_sandbox first-parent-only
base="$(git -C "$D" rev-parse HEAD)"
publish acme-web "$base"
git_q "$D" checkout -b side
echo side >>"$D/README.md"
git_q "$D" add -A
git_q "$D" commit -m "a commit on the PR side"
side="$(git -C "$D" rev-parse HEAD)"
publish acme-bff "$side"
git_q "$D" checkout main
git_q "$D" merge --no-ff -m "Merge pull request" side
merge_change_to acme-web/package.json
if [ "$(git -C "$D" rev-list "$side..HEAD^" --count)" -ge 1 ] \
  && git -C "$D" merge-base --is-ancestor "$side" 'HEAD^'; then
  ok "the side commit is reachable from HEAD^, so only --first-parent excludes it"
else
  no "the fixture is not what this case claims"
fi
run_retag
expect_status 0
expect_left_alone acme-bff
expect_says "::notice"

case_header "the walk is bounded at 100 commits"
# commit-tree rather than `git commit`: 101 of them, and the case still costs a
# second.
extend_main_by() {
  local i commit tree
  commit="$(git -C "$D" rev-parse HEAD)"
  tree="$(git -C "$D" rev-parse 'HEAD^{tree}')"
  i=0
  while [ "$i" -lt "$1" ]; do
    commit="$(git -C "$D" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$commit" -m "step $i")"
    i=$((i + 1))
  done
  git_q "$D" update-ref refs/heads/main "$commit"
  git_q "$D" reset --hard main
}
new_sandbox walk-reaches-hundred
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
extend_main_by 99
merge_change_to acme-web/package.json
if [ "$(git -C "$D" rev-list --first-parent --count "$base..HEAD^")" = 99 ] \
  && [ "$(git -C "$D" rev-parse "HEAD~100")" = "$base" ]; then
  ok "the ancestor is exactly the hundredth commit back"
else
  no "the fixture is not what this case claims"
fi
run_retag
expect_status 0
expect_retagged acme-bff "$base"

new_sandbox walk-stops-past-hundred
publish_all HEAD
extend_main_by 100
merge_change_to acme-web/package.json
run_retag
expect_status 0
expect_left_alone acme-bff
expect_says "::notice"

# --- Never the floating tag -------------------------------------------------
case_header "the floating tags are never a source, even when nothing else exists"
new_sandbox never-floating
for repo in $(all_repos); do
  printf 'ghcr.io/acme/%s:latest\nghcr.io/acme/%s:main\n' "$repo" "$repo" >>"$D/registry"
done
merge_change_to acme-web/package.json
run_retag
expect_status 0
expect_no_tag_written
if grep -qE ':(latest|main)( |$)' "$D/docker.log"; then
  no "the script asked about a floating tag: $(grep -E ':(latest|main)( |$)' "$D/docker.log" | head -3)"
else
  ok "no floating tag was even looked at"
fi

case_header "the word itself is not in the script"
if [ ! -f "$SCRIPT" ]; then
  no "$SCRIPT does not exist"
elif grep -qi 'latest' "$SCRIPT"; then
  no "retag-unchanged.sh contains it: $(grep -ni 'latest' "$SCRIPT" | head -3)"
else
  ok "retag-unchanged.sh never says it"
fi

# --- Tags already there -----------------------------------------------------
case_header "a tag already at HEAD is left alone, and counts as a build"
# The build beat this workflow to it. Reading that as "nothing happened here"
# would strand the other four.
new_sandbox head-tag-exists
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
publish acme-bff HEAD
run_retag
expect_status 0
expect_left_alone acme-bff
expect_retagged acme-web "$base"

case_header "a re-run after a partial retag finishes the set"
new_sandbox rerun-after-partial
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-bff/manage.py
publish acme-web HEAD
run_retag
expect_status 0
expect_left_alone acme-web
expect_retagged acme-gateway-auth "$base"

# --- Failing closed ---------------------------------------------------------
case_header "a workflow with no push paths fails closed and retags nothing"
new_sandbox empty-derivation-paths
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
awk '
  /^  push:/ { in_push = 1; print; next }
  /^  pull_request:/ { in_push = 0 }
  in_push && /^    paths:/ { dropping = 1; next }
  dropping && /^      / { next }
  { dropping = 0; print }
' "$D/.github/workflows/docker-auth.yml" >"$D/auth.new"
mv "$D/auth.new" "$D/.github/workflows/docker-auth.yml"
git_q "$D" add -A
git_q "$D" commit -m "docker-auth lost its paths"
merge_change_to acme-bff/manage.py
run_retag
expect_status 1
expect_says "acme-gateway-auth"
expect_no_tag_written

# graav-app's case "an image no build workflow publishes fails closed" has no
# equivalent here: release-images.sh derives the release list FROM the
# docker-*.yml workflows, so an image with no publisher cannot be listed.

case_header "an empty release list fails closed"
new_sandbox empty-derivation-images
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
sed -i.bak '/images: ghcr/d' "$D"/.github/workflows/docker-*.yml && rm -f "$D"/.github/workflows/*.bak
git_q "$D" add -A
git_q "$D" commit -m "no images"
merge_change_to acme-bff/manage.py
run_retag
expect_status 1
expect_no_tag_written

case_header "a negated path filter is not something this script can honour"
new_sandbox negated-path
add_push_path "!acme-web/docs/**"
git_q "$D" add -A
git_q "$D" commit -m "a negated filter"
publish_all HEAD
merge_change_to acme-bff/manage.py
run_retag
expect_status 1
expect_says "acme-web/docs"
expect_no_tag_written

case_header "a registry error is not evidence that a tag is missing"
# Reading `denied` as absence would walk past the real ancestor to an older one.
new_sandbox registry-denied
base="$(git -C "$D" rev-parse HEAD)"
publish_all "$base"
merge_change_to acme-web/package.json
run_retag DENY_REF_MATCHING=acme-svc-intel
expect_status 1
expect_says "denied"
expect_no_tag_written

case_header "a failed retag is red"
new_sandbox create-fails
publish_all HEAD
merge_change_to acme-bff/manage.py
run_retag CREATE_FAILS=1
if [ "$STATUS" -ne 0 ]; then ok "exit $STATUS"; else no "expected a failure"; fi

case_header "a shallow clone cannot walk, and says what to change"
new_sandbox shallow-clone
publish_all HEAD
merge_change_to acme-bff/manage.py
git clone -q --depth 1 --branch main "file://$D" "$D-shallow" >/dev/null 2>&1
cp -R "$D/bin" "$D-shallow/bin"
cp "$D/registry" "$D/docker.log" "$D-shallow/"
D="$D-shallow"
run_retag
expect_status 1
expect_says "fetch-depth: 0"
expect_no_tag_written

case_header "an empty owner fails closed"
new_sandbox no-owner
publish_all HEAD
merge_change_to acme-bff/manage.py
run_retag OWNER=
expect_status 1
expect_no_tag_written

printf '\n%s assertions passed, %s failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
  echo "FAIL: retag-unchanged.sh does not behave as its header says."
  exit 1
fi
if [ "$passed" -eq 0 ]; then
  echo "FAIL: zero assertions ran — the harness is broken, not the script."
  exit 1
fi
echo "OK: an image is retagged only from an ancestor proven identical over its paths."
