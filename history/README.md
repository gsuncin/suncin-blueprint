# history/

Closed workstreams and answered questions, kept **verbatim** — nothing
summarised. Sibling of `releases/`, and the counterpart of `specs/`:

| Directory | Holds |
|---|---|
| `specs/` | only what is still open |
| `history/` | only what shipped |
| `releases/` | one note per merged PR — the record of what shipped |

**A spec changes folder the moment it ships**, and that move rides in the same
PR as the release note, never as a followup.

## Why this exists

A spec that ships and stays in `specs/` reads, to the next session, exactly
like a spec that is still open. The cost is concrete: a session can plan and
rebuild a whole wave of already-merged work, because the file describing it
still says "pending" — and one of the agents it launches can land *behind* what
the default branch already had.

So before trusting any spec: `git log origin/main` and `releases/`. A
workstream file describing a task as pending is not evidence the task is
pending. `releases/` and the git history are.
