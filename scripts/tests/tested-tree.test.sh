#!/usr/bin/env bash
# Tests for .github/scripts/tested-tree.sh. No token, no network, a few seconds.
#
# Why these exist (specs def1b6f0, D-5): the script decides whether the suites
# in front of a production deploy may be skipped on the push to main. Skipping
# wrongly ships an untested image; skipping never costs only minutes. So every
# doubtful case below must answer skip=false, and only an exact tree match may
# answer skip=true.
#
# Two seams, both real rather than test-only. `gh` is a shim on PATH that keeps
# statuses the way GET /commits/<sha>/statuses does: every entry, newest first,
# each with its creator, 30 to a page unless per_page says otherwise and never
# more than 100. Read off a live response on 2026-10-30: a status posted with
# GITHUB_TOKEN carries creator.login "github-actions[bot]", type Bot. The history
# is a real git repository with real merge commits, because "the merge commit's
# second parent" and "fetch-depth 2 is enough" are facts about git and not about
# this script.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/.github/scripts/tested-tree.sh"

for tool in jq git python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FAIL: $tool is not installed, and every case here needs it."
    exit 1
  fi
done

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
case_header() { printf '\n=== %s\n' "$1"; }

git_q() { git -C "$1" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "${@:2}" >/dev/null 2>&1; }

# One sandbox per case: `main` with one commit, and a branch `pr` one commit
# ahead of it, which is the shape of staging on a release PR.
new_sandbox() {
  local d="$WORK/$1"
  mkdir -p "$d/bin" "$d/statuses" "$d/repo"
  : >"$d/gh.log"

  cat >"$d/bin/gh" <<'SHIM'
#!/usr/bin/env bash
# Answers from $GH_STATE instead of the network. An unrecognised call is a loud
# failure, never an empty answer that looks like "no status".
set -euo pipefail
printf '%s\n' "$*" >>"$GH_LOG"
if [ "${GH_FAILS:-0}" = 1 ]; then
  echo "gh: Resource not accessible by integration (HTTP 403)" >&2
  exit 1
fi
if [ "${GH_MALFORMED:-0}" = 1 ]; then
  echo '<html>bad gateway</html>'
  exit 0
fi
if [ "${GH_ANSWERS_AN_OBJECT:-0}" = 1 ]; then
  echo '{"message":"Not Found","status":"404"}'
  exit 0
fi
case "${1:-} ${2:-} ${3:-}" in
  "api -X POST")
    sha="${4##*/}"
    shift 4
    state="" context="" description=""
    while [ "$#" -gt 0 ]; do
      case "$2" in
        state=*) state="${2#state=}" ;;
        context=*) context="${2#context=}" ;;
        description=*) description="${2#description=}" ;;
      esac
      shift 2
    done
    file="$GH_STATE/$sha.json"
    [ -f "$file" ] || echo '[]' >"$file"
    jq --arg s "$state" --arg c "$context" --arg d "$description" \
      --arg who "${GH_ACTOR:-github-actions[bot]}" \
      '[{state: $s, context: $c, description: $d, creator: {login: $who}}] + .' \
      "$file" >"$file.new"
    mv "$file.new" "$file"
    ;;
  *)
    case "${2:-}" in
      repos/*/commits/*/statuses | repos/*/commits/*/statuses\?*)
        path="${2%%\?*}"
        sha="${path%/statuses}"
        sha="${sha##*/}"
        per_page=30
        case "$2" in *per_page=*) per_page="${2##*per_page=}" ;; esac
        [ "$per_page" -le 100 ] || per_page=100
        file="$GH_STATE/$sha.json"
        if [ -f "$file" ]; then
          jq --argjson n "$per_page" '.[:$n]' "$file"
        else
          echo '[]'
        fi
        ;;
      *)
        echo "gh shim: unexpected call: gh $*" >&2
        exit 64
        ;;
    esac
    ;;
esac
SHIM
  chmod +x "$d/bin/gh"

  git_q "$d/repo" init -b main
  echo base >"$d/repo/base.txt"
  git_q "$d/repo" add -A
  git_q "$d/repo" commit -m base
  git_q "$d/repo" checkout -b pr
  echo change >"$d/repo/change.txt"
  git_q "$d/repo" add -A
  git_q "$d/repo" commit -m "the work the PR carries"
  git_q "$d/repo" checkout main
  echo "$d"
}

# What GitHub builds at refs/pull/N/merge and what a pull_request run checks
# out: a merge of the PR into its base that is not on any branch.
checkout_merge_ref() {
  git_q "$1/repo" checkout --detach main
  git_q "$1/repo" merge --no-ff -m "Merge pr into main (the test merge)" pr
}

merge_pr_into_main() {
  git_q "$1/repo" checkout main
  git_q "$1/repo" merge --no-ff -m "Merge pull request #1 from acme/staging" pr
}

pr_head() { git -C "$1/repo" rev-parse pr; }

run_script() {
  # run_script <sandbox> <subcommand> <suite> [ENV=val ...]
  local d="$1" subcommand="$2" suite="$3"
  shift 3
  : >"$d/output"
  OUT="$(cd "$d/repo" && env -u GITHUB_EVENT_NAME -u GITHUB_REF \
    PATH="$d/bin:$PATH" GH_LOG="$d/gh.log" GH_STATE="$d/statuses" \
    GITHUB_REPOSITORY=acme/repo GITHUB_OUTPUT="$d/output" "$@" \
    "$SCRIPT" "$subcommand" "$suite" 2>&1)"
  STATUS=$?
  printf '%s\n' "$OUT" | sed 's/^/    | /'
}

lookup_on_main() {
  local d="$1"
  shift
  run_script "$d" lookup bff GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main "$@"
}

# The whole of a pull_request run's half: check out the merge, and record it.
record_on_pr() {
  local d="$1"
  checkout_merge_ref "$d"
  run_script "$d" record bff PR_HEAD_SHA="$(pr_head "$d")"
}

# A status somebody other than the record job posts on the PR head, through the
# same shim, so it lands in front of whatever is already there.
post_status() {
  # post_status <sandbox> <actor> <state> <context> <description>
  PATH="$1/bin:$PATH" GH_LOG="$1/gh.log" GH_STATE="$1/statuses" GH_ACTOR="$2" gh api -X POST \
    "repos/acme/repo/statuses/$(pr_head "$1")" \
    -f "state=$3" -f "context=$4" -f "description=$5"
}

head_tree() { git -C "$1/repo" rev-parse 'HEAD^{tree}'; }

# <count> newer statuses for other contexts, in one write rather than one gh
# call each.
bury_under_newer_statuses() {
  local d="$1" count="$2" file
  file="$d/statuses/$(pr_head "$d").json"
  jq --argjson n "$count" \
    '[range(0; $n) | {state: "success", context: "ci/other-\(.)", description: "noise",
                      creator: {login: "some-other-app[bot]"}}] + .' \
    "$file" >"$file.new"
  mv "$file.new" "$file"
}

expect_skip() {
  local want="$1" got
  got="$(grep -c "^skip=$want\$" "$D/output")"
  if [ "$got" = 1 ] && [ "$(wc -l <"$D/output" | tr -d ' ')" = 1 ]; then
    ok "GITHUB_OUTPUT holds exactly skip=$want"
  else
    no "expected exactly one line skip=$want in GITHUB_OUTPUT, got: [$(tr '\n' ' ' <"$D/output")]"
  fi
  if [ "$STATUS" -eq 0 ]; then ok "exit 0"; else no "expected exit 0, got $STATUS"; fi
}

# --- record ------------------------------------------------------------------
case_header "record posts the tested merge's tree on the PR head"
D="$(new_sandbox record-shape)"
checkout_merge_ref "$D"
merge_tree="$(git -C "$D/repo" rev-parse 'HEAD^{tree}')"
run_script "$D" record bff PR_HEAD_SHA="$(pr_head "$D")"
if [ "$STATUS" -eq 0 ]; then ok "exit 0"; else no "expected exit 0, got $STATUS"; fi
stored="$D/statuses/$(pr_head "$D").json"
if [ -f "$stored" ] \
  && [ "$(jq -r '.[0].description' "$stored")" = "$merge_tree" ] \
  && [ "$(jq -r '.[0].state' "$stored")" = success ] \
  && [ "$(jq -r '.[0].context' "$stored")" = tested-tree/bff ]; then
  ok "status on the PR head: success, tested-tree/bff, the merge's tree"
else
  no "the status on the PR head is not what lookup will read: $(cat "$stored" 2>/dev/null)"
fi
if [ -f "$D/statuses/$(git -C "$D/repo" rev-parse HEAD).json" ]; then
  no "the status went on the merge ref, which main never sees"
else
  ok "nothing was posted on the throwaway merge ref"
fi

case_header "record refuses to run without the PR head"
D="$(new_sandbox record-no-head)"
checkout_merge_ref "$D"
run_script "$D" record bff
if [ "$STATUS" -ne 0 ]; then ok "exit $STATUS"; else no "expected a failure"; fi

case_header "record says so when the API refuses"
D="$(new_sandbox record-api-failure)"
checkout_merge_ref "$D"
run_script "$D" record bff PR_HEAD_SHA="$(pr_head "$D")" GH_FAILS=1
if [ "$STATUS" -ne 0 ]; then ok "exit $STATUS"; else no "expected a failure"; fi

# --- lookup: the one case that skips ----------------------------------------
case_header "the merge commit has exactly the tree the PR tested: skip"
D="$(new_sandbox exact-match)"
record_on_pr "$D"
merge_pr_into_main "$D"
lookup_on_main "$D"
expect_skip true

case_header "fetch-depth 2 is enough to see the second parent"
D="$(new_sandbox shallow-depth-two)"
record_on_pr "$D"
merge_pr_into_main "$D"
git clone -q --depth 2 --branch main "file://$D/repo" "$D/shallow" >/dev/null 2>&1
mv "$D/repo" "$D/full"
mv "$D/shallow" "$D/repo"
if [ "$(git -C "$D/repo" rev-parse --is-shallow-repository)" = true ]; then
  ok "the clone really is shallow"
else
  no "the clone is not shallow, so this case proves nothing"
fi
lookup_on_main "$D"
expect_skip true

# --- lookup: every doubtful case runs the tests ------------------------------
case_header "main moved under the PR, so the merge is a tree nobody tested"
D="$(new_sandbox different-tree)"
record_on_pr "$D"
git_q "$D/repo" checkout main
echo hotfix >"$D/repo/hotfix.txt"
git_q "$D/repo" add -A
git_q "$D/repo" commit -m "a hotfix landed on main"
merge_pr_into_main "$D"
lookup_on_main "$D"
expect_skip false

case_header "a squash merge has no second parent, even with an identical tree"
D="$(new_sandbox no-second-parent)"
record_on_pr "$D"
git_q "$D/repo" checkout main
git_q "$D/repo" merge --squash pr
git_q "$D/repo" commit -m "squashed"
lookup_on_main "$D"
expect_skip false

case_header "the API fails"
D="$(new_sandbox api-failure)"
record_on_pr "$D"
merge_pr_into_main "$D"
lookup_on_main "$D" GH_FAILS=1
expect_skip false

case_header "the API answers something that is not JSON"
D="$(new_sandbox api-malformed)"
record_on_pr "$D"
merge_pr_into_main "$D"
lookup_on_main "$D" GH_MALFORMED=1
expect_skip false

case_header "nothing was recorded on the PR head"
D="$(new_sandbox missing-status)"
merge_pr_into_main "$D"
lookup_on_main "$D"
expect_skip false

case_header "the same tree passed for another suite"
D="$(new_sandbox other-suite)"
record_on_pr "$D"
merge_pr_into_main "$D"
run_script "$D" lookup web GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main
expect_skip false

case_header "the API answers JSON that is not a list"
D="$(new_sandbox api-object)"
record_on_pr "$D"
merge_pr_into_main "$D"
lookup_on_main "$D" GH_ANSWERS_AN_OBJECT=1
expect_skip false

case_header "a status that is not success, on the right tree"
D="$(new_sandbox not-success)"
merge_pr_into_main "$D"
post_status "$D" 'github-actions[bot]' failure tested-tree/bff "$(head_tree "$D")"
lookup_on_main "$D"
expect_skip false

# --- who said so -------------------------------------------------------------
# Status-write is a wider permission than it looks, and a forged status leaves
# nothing in the tree. Only the record job's own token may vouch for a suite.
case_header "a person's status on the exact tree does not skip the suite"
D="$(new_sandbox forged-by-a-person)"
merge_pr_into_main "$D"
post_status "$D" gsuncin success tested-tree/bff "$(head_tree "$D")"
lookup_on_main "$D"
expect_skip false

case_header "another app's status on the exact tree does not skip the suite"
D="$(new_sandbox forged-by-an-app)"
merge_pr_into_main "$D"
post_status "$D" 'github-actions-lookalike[bot]' success tested-tree/bff "$(head_tree "$D")"
lookup_on_main "$D"
expect_skip false

# The newest entry decides. An `any` over the list would read the real record
# underneath and skip the suite over the top of whatever came after it.
case_header "a forged status after the real one: the newest entry decides"
D="$(new_sandbox forged-after-real)"
record_on_pr "$D"
merge_pr_into_main "$D"
post_status "$D" gsuncin success tested-tree/bff "$(head_tree "$D")"
lookup_on_main "$D"
expect_skip false

case_header "a failed status after the real one: the newest entry decides"
D="$(new_sandbox failed-after-real)"
record_on_pr "$D"
merge_pr_into_main "$D"
post_status "$D" 'github-actions[bot]' failure tested-tree/bff "$(head_tree "$D")"
lookup_on_main "$D"
expect_skip false

case_header "the real record after a forged status still skips"
D="$(new_sandbox real-after-forged)"
post_status "$D" gsuncin success tested-tree/bff "not-a-tree"
record_on_pr "$D"
merge_pr_into_main "$D"
lookup_on_main "$D"
expect_skip true

# --- paging ------------------------------------------------------------------
# The list is paged. The newest entry for a context on the page we read IS the
# newest there is, because the list is newest first, so a miss can only ever
# mean skip=false. These pin both halves.
case_header "forty newer statuses push it off GitHub's default page, not off ours"
D="$(new_sandbox past-the-default-page)"
record_on_pr "$D"
merge_pr_into_main "$D"
bury_under_newer_statuses "$D" 40
lookup_on_main "$D"
expect_skip true

case_header "a hundred newer statuses push it off the page: a miss runs the tests"
D="$(new_sandbox off-the-page)"
record_on_pr "$D"
merge_pr_into_main "$D"
bury_under_newer_statuses "$D" 100
lookup_on_main "$D"
expect_skip false

case_header "a tag push is never skipped, even on the exact tree"
D="$(new_sandbox tag-push)"
record_on_pr "$D"
merge_pr_into_main "$D"
run_script "$D" lookup bff GITHUB_EVENT_NAME=push GITHUB_REF=refs/tags/v1.2.3
expect_skip false

case_header "a dispatch is never skipped, even on the exact tree"
D="$(new_sandbox dispatch)"
record_on_pr "$D"
merge_pr_into_main "$D"
run_script "$D" lookup bff GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF=refs/heads/main
expect_skip false

case_header "a pull_request run is never skipped"
D="$(new_sandbox pull-request)"
record_on_pr "$D"
run_script "$D" lookup bff GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/1/merge
expect_skip false

case_header "a push to a branch that is not main is never skipped"
D="$(new_sandbox other-branch)"
record_on_pr "$D"
merge_pr_into_main "$D"
run_script "$D" lookup bff GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/staging
expect_skip false

case_header "an empty suite name is a failure, so the gate stops the image"
D="$(new_sandbox empty-suite)"
record_on_pr "$D"
merge_pr_into_main "$D"
run_script "$D" lookup ""
if [ "$STATUS" -ne 0 ]; then ok "exit $STATUS"; else no "expected a failure"; fi
if grep -q 'skip=true' "$D/output"; then no "a usage error said skip=true"; else ok "no skip=true"; fi

# --- the guard, read out of the real workflows -------------------------------
# `needs` on a skipped job skips its dependents by default, so a tests job that
# the gate skipped would mean no image and no deploy; and a guard written to
# avoid that can easily let an untested image through. These rows are what
# D-5 says, evaluated against the `if:` the workflow really carries, so a
# reworded guard cannot pass by matching a string.
case_header "build-and-push's guard, as written in each workflow, over every outcome"
guard_of() {
  awk '
    /^  build-and-push:[[:space:]]*$/ { in_job = 1; next }
    in_job && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { in_job = 0 }
    in_job && /^    if:/ { sub(/^    if:[[:space:]]*/, ""); print; exit }
  ' "$1"
}
evaluate_guard() {
  # <expression> <gate result> <tests result> <skip> <event> <cancelled>
  python3 -I -c '
import re, sys
expr, gate, tests, skip, event, cancelled = sys.argv[1:7]
m = re.fullmatch(r"\$\{\{(.*)\}\}", expr.strip())
if not m:
    sys.exit("the guard is not a ${{ }} expression: " + expr)
body = m.group(1)
body = body.replace("!cancelled()", " (not cancelled) ")
body = body.replace("&&", " and ").replace("||", " or ")
for name, value in (("needs.gate.outputs.skip", "skip"), ("needs.gate.result", "gate"),
                    ("needs.tests.result", "tests"), ("github.event_name", "event")):
    body = body.replace(name, value)
result = eval(body.strip(), {"__builtins__": {}},
              {"gate": gate, "tests": tests, "skip": skip, "event": event,
               "cancelled": cancelled == "true"})
print("image" if result else "no-image")
' "$@"
}
workflows_with_guard=0
for wf in docker-bff docker-web; do
  file="$ROOT/.github/workflows/$wf.yml"
  guard="$(guard_of "$file")"
  if [ -z "$guard" ]; then
    no "$wf.yml: build-and-push has no if:"
    continue
  fi
  workflows_with_guard=$((workflows_with_guard + 1))
  # gate     tests     skip   event              cancelled  outcome
  while read -r gate tests skip event cancelled want reason; do
    [ "$skip" = "-" ] && skip=""
    got="$(evaluate_guard "$guard" "$gate" "$tests" "$skip" "$event" "$cancelled" 2>&1)"
    if [ "$got" = "$want" ]; then
      ok "$wf: $reason -> $want"
    else
      no "$wf: $reason -> wanted $want, got $got"
    fi
  done <<'ROWS'
success   success   false push              false image    tests ran and passed
success   skipped   true  push              false image    the gate skipped them on an exact tree
success   failure   false push              false no-image a red suite
success   skipped   false push              false no-image skipped by anything but the gate
failure   skipped   -     push              false no-image a failed gate
cancelled skipped   -     push              false no-image a cancelled gate
skipped   skipped   -     push              false no-image a skipped gate
success   cancelled false push              false no-image tests cancelled
success   skipped   true  push              true  no-image the run was cancelled
success   success   false pull_request      false no-image a PR never builds an image
success   success   false workflow_dispatch false image    a dispatch
ROWS
done
if [ "$workflows_with_guard" -eq 0 ]; then
  no "no workflow carries the guard, so nothing above ran"
fi

printf '\n%s assertions passed, %s failed\n' "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
  echo "FAIL: tested-tree.sh or the build guard does not behave as D-5 says."
  exit 1
fi
if [ "$passed" -eq 0 ]; then
  echo "FAIL: zero assertions ran — the harness is broken, not the script."
  exit 1
fi
echo "OK: only an exact tree skips the suites, and only a passed or gate-skipped suite publishes."
