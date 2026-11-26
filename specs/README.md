# specs/

Specification-driven development. Specs are written before code and edited when
reality disagrees — **a spec that no longer matches the tree is a bug in the
spec.**

## Layout

```
specs/
├── README.md            ← this file: conventions + index
├── CONSTITUTION.md      ← non-negotiable rules (C-1 … C-12)
├── ORCHESTRATION.md     ← multi-agent runbook + ready-to-paste Agent calls
├── QUESTIONS.md         ← every open question, grouped by who can answer it
├── DECISIONS.md         ← ADR log
├── TECH-DEBT.md         ← compromises we carry
├── BACKLOG.md           ← pending work not inside a workstream
├── RELEASES.md          ← release-note convention
├── WS-000-template.md   ← copy this to start a workstream
├── 00X-<slug>.md        ← one file per workstream
└── research/            ← provider findings that specs cite
```

Release notes live in `releases/` at the repo root, not here — an agent
starting cold in a fresh worktree reads that directory from disk with no API
call, no token and no network.

**`history/` is the sibling of `releases/`, and it is where a spec goes the
moment it ships.** `specs/` holds only what is still open; `history/` holds
only what shipped, verbatim, nothing summarised.

**The move rides in the same PR as the release note, never as a followup.**
This is not tidiness. A spec that ships and stays in `specs/` reads, to the
next session, exactly like a spec that is still open — and the cost of that is
concrete: a session can plan and rebuild an entire wave of work that is already
merged, because the file describing it still says "pending". Before trusting
any spec, read `git log origin/develop` and `releases/`. A workstream file
describing a task as pending is not evidence the task is pending.

## Before you file a `Q-n`, try to close it

**Discovering an unknown is a successful outcome — but filing it is the last
resort, not the first.** Guessing past it is wrong; so is parking a question
you could have answered yourself. Three rungs, in order:

1. **Answer it yourself** — from the repo, the git history, `releases/`,
   `history/`, and the live provider documentation. Most questions agents raise
   die here.
2. **Ask a human, in words, with your recommendation.** Not "see Q-3.22" — the
   question, spelled out, and what you would do.
3. **Only then file it**, with an owner.

The tell that a rung was skipped is a report that diagnoses the problem and
declares it blocked in the same sentence.

## A `Q-n` id is not a question

**Never name a question by its id alone.** `Q-3.22` is not a question — it is a
lookup someone else has to perform, and the person who has to perform it is
usually the one who could have answered it in a sentence.

Write the id *and* the question, in words, every time: in reports, PR bodies,
release notes and issue titles.

## Four registers, four jobs — do not merge them

| File | Holds | Not |
|---|---|---|
| `BACKLOG.md` | Work not started | Things already shipped with a compromise |
| `TECH-DEBT.md` | Compromises already live in production | Work nobody has begun |
| `DECISIONS.md` | Why we chose what we chose | What we have not decided |
| `QUESTIONS.md` | What nobody has answered yet | Answers — those go back to the workstream |

## The shape of a workstream file

Five sections, always these five, always in this order:

| Section | Contains | Rule |
|---|---|---|
| `## Problem` | Why now, what breaks without it | **No solutions here** |
| `## Decisions` | Choices already made, and their rationale | Each gets a `D-n` id so tasks can cite it |
| `## Open questions` | What must be answered before or while building | Each gets a `Q-n` id **and an owner** |
| `## Design` | Architecture, contracts, file-level changes | The "how" |
| `## Tasks` | Ordered, atomic, agent-assignable units | Each gets a `T-n` id, a Definition of Done, **and an agent** |

## Conventions

- **IDs are stable. Never renumber.** A superseded decision is struck through
  in place: `~~D-3~~ superseded by D-9`. A resolved question keeps its id and
  gains the answer and a date. Deleting an id orphans every reference to it.
- **One workstream per branch**, named `spec/00X-<slug>`, and one workstream per
  PR. A PR that spans two workstreams should have been two PRs.
- **Every task names its agent.** A task with no agent is not ready to launch.
- **Research is cited with a date.** "the provider returns X" is worthless
  without "confirmed against the live docs on 2026-08-15" (C-10).
- **Append, do not rewrite history.** When a question is reopened, add
  `## Q-8.5 REOPENED AND REPLACED — <date>` and keep the old resolution under
  `## HISTORY — Q-8.5 resolved as Direction A (<date>, superseded)`. The
  reasoning that was abandoned is why the next person does not re-propose it.

## Index

| Workstream | Status |
|---|---|
| *(none yet — copy `WS-000-template.md` to start one)* | |

Shipped so far: `releases/R-001-boilerplate.md`.
