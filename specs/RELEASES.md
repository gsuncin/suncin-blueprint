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

## The identifier

**`R-YYYY-MM-DD-xxxxxx`** — the date the note was written, plus six lowercase
hex digits. The filename is `R-YYYY-MM-DD-xxxxxx-<slug>.md`.

```bash
printf 'R-%s-%s\n' "$(date +%F)" "$(openssl rand -hex 3)"
```

**`R-NNN` is retired, and the older notes keep their names.** Both formats stay
valid forever: `find-release-note.sh` accepts either, and the tag trigger in
`release-notes.yml` matches both.

### Why a sequence stopped working

A number is read at write time and claimed at merge time, and **nothing
reserves it in between**. Two branches in flight both read "the next free
number is 64", both write `R-064-<their own slug>.md`, and git merges them
without a conflict — because they are two different filenames. The collision
is only visible when someone pushes the tag and the workflow finds two notes
for one identifier and refuses to publish either.

A random suffix cannot collide that way, and the date keeps the directory
sorted and browsable. What is lost is "which release came first", which the
git history already answers better.

## Rules

- **One note per merged PR.** A PR that spans two workstreams should have been
  two PRs.
- **An identifier is never reused**, including for a tag. A note that was
  abandoned keeps its identifier out of circulation forever.
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

## The two-branch flow

**Branch from `develop`. One workstream per PR. `develop` merges to `main` a
release at a time.**

### Why

A feature PR straight onto `main` makes `main` the integration branch, which
means every merge is simultaneously "this work is done" and "this is what
ships". Those are two different decisions with two different risk profiles, and
collapsing them is what makes a release a thing people are afraid of.

Splitting them costs one extra merge per release and buys: a place for work to
land and be integrated with other work before anyone commits to shipping it,
and a `main` that is always exactly what is deployed.

### What each merge carries

| Merge | Carries |
|---|---|
| feature → `develop` | the reviews, a release note in `releases/`, the spec moved to `history/` — all in the same PR |
| `develop` → `main` | the tag and the GitHub release, because **this** is the merge that ships |

A feature PR still carries everything it always did. What changed is where it
lands.

**Long-lived personal accumulation branches are still wrong**, for the reason
they always were: they strand later work on a stale base. `develop` is not one
of those — it is short-lived by construction, because a release empties it.

### A worktree-isolated agent branches from `develop`

Not from `main`, which now trails by a release, and not from your branch. An
agent branching from `main` would be working against a tree that is
deliberately old. Keep `develop` current rather than working around this.

## What a merge requires

Every one of these, in this order. None is optional, and none is a followup:

1. **A green suite, output pasted.** A sentence claiming success is not
   evidence (C-8).
2. **The reviews the diff calls for** — the table in CLAUDE.md decides which,
   so it is not a judgement call. Before the merge: after it, a finding is an
   incident.
3. **Every review comment cleared**, scored and answered — the section below.
4. **A release note in `releases/`**, named for the identifier above.
5. **The spec moved from `specs/` to `history/`**, in the SAME PR as the note.
   `specs/` holds only what is open; `history/` holds only what shipped. A spec
   that ships and stays in `specs/` is how eighteen questions come to be marked
   open after they were answered.

**The merge itself is the one step a person confirms.** Everything above can be
checked mechanically; whether this should ship now cannot.

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
