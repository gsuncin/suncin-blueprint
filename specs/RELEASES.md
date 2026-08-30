# Releases

Three layers. **They compose — do not duplicate them.**

| | `.changelog.md` | Release note (`R-NNN`) | Production release |
|---|---|---|---|
| Written by | `scripts/precommit-changelog-docs.sh`, automatically | Whoever merges | Repo owner, at deploy |
| Trigger | Every commit | Every merge to `main` | A deliberate deploy |
| Identity | Date heading | `R-NNN`, sequential | `vMAJOR.MINOR.PATCH` tag |
| Content | Mechanical: scope + file list, stamped `Review required` | What it means, and the test evidence | Checklist, rollback plan |

The pre-commit hook records *which paths changed*. The release note says *what
the change means*. The `Review required` stamp is the seam between them.

## One source, two surfaces

`releases/R-NNN-<slug>.md` is written in the repo. Pushing the tag `R-NNN` runs
`.github/workflows/release-notes.yml`, which finds that file, uses its H1 as
the release title and its body as the body, and creates — or updates — the
GitHub Release.

The file is the source. An agent starting cold in a fresh worktree reads that
directory from disk with no API call, no token and no network.

## Rules

- **One note per merged PR.** A PR that spans two workstreams should have been
  two PRs.
- **`R-NNN` numbers are never reused**, including for a tag. If `R-004` was
  abandoned, `R-004` stays absent from the sequence forever. Check `releases/`
  for the next free number — not the highest you remember.
- **A reverted release keeps its note**, with `Status: reverted` and a line
  saying what happened. Deleting it removes the reason the next person needs.
- **`"Frontend: none"` is written explicitly, never omitted.** An empty section
  and a forgotten section look identical.
- **The TDD section reports real numbers from a real run**, pasted. Not "all
  tests pass".
- **Spec deltas are mandatory** when a decision changed during the work.

## Template

```markdown
# R-NNN — <one-line summary>

**Date:** <YYYY-MM-DD>
**Workstream:** WS-00X · **Tasks:** T-n, T-m
**Agent:** `<agent-name>` (worktree) · reviewed by `security-agent`
**PR:** #NN · **Commit:** <sha>
**Status:** merged | reverted

---

## Implemented

What shipped, in prose, one subsection per meaningful change. Say what it means
for a user or an operator, not which files moved.

## TDD coverage

The tests written first, and the real output of the real run.

## Backend
## Frontend
## Infrastructure

One line each, or the word `none`.

## Also changed

Incidental fixes that rode along.

## Spec deltas

Which `D-n` / `Q-n` / `T-n` changed, and how.

## Migration notes

What an operator must do, in order. `none` if nothing.
```

Later notes tend to grow three more sections, and they are worth adding when
they apply: `## Security review` (findings, severity-ordered, each with the fix
that landed before merge), `## Open questions raised` (a table with owners), and
`## Before deploying` (anything that must be true first).

A release note may **propose** a Constitution amendment — "this incident shows
C-8's coverage table is missing X" — but may not make one. The Constitution is
not an agent's to edit.

## Before you merge: review comments are a gate

**A PR with an unanswered review comment is not ready to merge, no matter how
green the suite is.** This applies to your own PRs, an agent's, and a bot's.

Two places to look, because they are different APIs:

```bash
# Top-level comments
gh pr view <PR> --comments

# Inline review threads — these do NOT show up above
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$pr){
        reviewThreads(first:100){
          nodes{ id isResolved isOutdated path line
                 comments(first:10){ nodes{ author{login} body } } } } } } }' \
  -F owner=<owner> -F repo=<repo> -F pr=<PR>
```

Or just run `./scripts/pr-review-gate.sh <PR>`, which does both and exits 1 if
anything is unresolved.

Every unresolved thread gets exactly one of two outcomes:

| Outcome | When | What you do |
|---|---|---|
| **Accept** | The comment is right, or the code is ambiguous enough that the reviewer's reading is reasonable | Change the code, push, reply linking the commit, then resolve |
| **Resolve without changing code** | Wrong, already handled elsewhere, out of scope, or a deliberate decision recorded in a spec | Reply with the reason — pointing at code, a spec, or a release note — then resolve |

**The reply is what makes it legitimate.** A resolved thread with no answer
destroys the reason for the decision, and the next reviewer raises the same
point.

Three cases where you **stop** instead of resolving:

1. The comment identifies a **Constitution violation**. Fix it; there is no
   version of this where you resolve and merge.
2. The comment **reopens a decision owned by a human**. Take it to them.
3. The comment **reveals an unknown**. Append a fresh `Q-n` to the workstream
   file and answer it before merging, or record why it can wait.
