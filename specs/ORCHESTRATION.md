# Orchestration

**Status (2026-08-29):** R-001 shipped the boilerplate itself — every
project, the gateway, the Terraform and the CI. No workstream has been run
from this file yet; `specs/` contains only the template.

> Keep this paragraph accurate. A stale status line at the top of this file is
> the single most expensive lie in the repo — it is what makes a session
> rebuild work that is already merged. If you are not sure, `git log
> origin/develop` and `releases/` are the truth.

## Agent roster

| Agent | Owns | Tools |
|---|---|---|
| `bff-agent` | `acme-bff` | Read, Write, Edit, Bash, Grep, Glob |
| `service-agent` | every `acme-svc-*`, `acme-gateway/auth` | Read, Write, Edit, Bash, Grep, Glob, WebFetch |
| `frontend-agent` | `acme-web` (app + landing entries) | Read, Write, Edit, Bash, Grep, Glob |
| `infra-agent` | `acme-tf`, `acme-gateway/traefik`, `.github/workflows` | Read, Write, Edit, Bash, Grep, Glob |
| `qa-agent` | Tests across every project | Read, Write, Edit, Bash, Grep, Glob |
| `security-agent` | Review only — **no Write, no Edit** | Read, Grep, Glob, Bash |
| `design-agent` | Review only, `acme-web/src` — **no Write, no Edit** | Read, Grep, Glob, Bash |
| `research-agent` | `specs/research/` only — **no Bash** | Read, Write, Edit, Grep, Glob, WebFetch, WebSearch |

## Orchestration rules

1. **One agent per project per wave.** Parallelism comes from agents working in
   *different* projects, or from `isolation: "worktree"`. Two agents in
   `acme-bff` will conflict.
2. **Research precedes implementation.** A task citing an unresolved `Q-n` does
   not launch. Send `research-agent` first.
3. **Human decisions are hard gates.** An agent that hits one stops and asks.
   It does not pick a default and note it — that is how a decision gets made by
   accident.
4. **`security-agent` and `design-agent` run on request, and before merge,
   never after.** If the request did not ask for a review, the orchestrator asks
   the user once, at the end of the task, naming the reviews the table in
   CLAUDE.md recommends; the merge waits for the answer. A subagent never asks
   and never launches one. A finding after the merge is an incident; before the
   merge it is a comment.
5. **TDD is mandatory and a green suite is the exit gate (C-8). Blocked is not
   done.**
6. **Brief a subagent with its task section and the `C-n`/`D-n` that bind it,
   never "read everything".** A prompt that sends an agent to read whole spec
   files spends its context before it writes a line.

## An uncommitted worktree is the most reliable way to lose work

**A worktree is not storage. Commit before you report, and never remove a
worktree without looking inside it.**

An agent finishes, writes a summary, and the worktree is cleaned up — with
uncommitted changes in it. The summary describes work that no longer exists,
and it reads exactly like work that does. This is the single most repeatable
way to lose a day here, which is why `scripts/hooks/warn-uncommitted-on-stop.sh`
blocks on a dirty tree rather than trusting anyone to remember.

`wip(scope):` is an honest subject line. An imperfect commit is recoverable;
a deleted worktree is not.

## Keeping `develop` current across machines and agents

A worktree-isolated agent branches from `develop` (RELEASES.md, the two-branch
flow). If `develop` is stale, every agent launched from it is working against a
tree that is missing the last release — and a prompt written against your
branch describes a repository the agent is not looking at.

So: fetch and fast-forward `develop` before launching a wave, not after
something looks wrong.

## Branching: how a wave is actually run

**An agent with `isolation: "worktree"` branches from `main`, never from the
orchestrator's branch.** So the rule that makes worktrees safe is: **`main` is
fast-forwarded at the end of every wave, before the next one is launched.**

1. `git fetch origin main` and confirm it contains everything this wave depends
   on. If it does not, merge first — do not work around it in the prompt.
2. Launch one agent per project, each with `isolation: "worktree"`.
3. **Agents commit on their own worktree branch. They do not push and do not
   open PRs.** The orchestrator integrates.
4. **Verify each branch yourself against the merge.** Run the suite. Do not
   trust reported numbers — a report is a claim, not evidence.
5. Merge, write the `R-NNN` note, fast-forward `main`, then
   `git worktree remove` and `git branch -D`.

### When worktrees are the wrong tool

If two agents must both see work that is not yet on `main`, worktrees cannot
help — they would each branch from a `main` that does not contain it.

In that case run them in the orchestrator's checkout, each confined to its own
project directory, and **forbid them every git command**. A `git add` from one
agent sweeps up the other's half-written files. The orchestrator commits per
project with explicit paths.

Either way, the cross-project contract — header names, status strings, URL
shapes — is fixed by the orchestrator *before* launch and given to both agents
**in identical words**, with instructions to *report* a mismatch rather than
renegotiate it.

## Handoff protocol

Every agent ends its run with, in this order:

0. **Proof the suite is green** — the actual printed output. Nothing else in
   this list matters if it is missing.
1. What else it ran, and what that printed.
2. Which spec ids it completed, and which it skipped and why.
3. New open questions, appended to the workstream file with fresh `Q-n` ids.
   **Discovering an unknown is a successful outcome, not a failure.**
4. Assumptions it made, stated explicitly.

**Agents do not launch other agents.**

## Ready-to-launch calls

Written to be self-contained: an agent starts cold and knows only what its
definition and this prompt tell it. **Spent calls are kept**, marked
`SPENT (R-0NN)`, as the record of what each agent was actually told.

```
subagent_type: bff-agent
description: <5 words>
isolation: worktree
prompt: |
  PRECONDITION — read before anything else:
    - specs/CONSTITUTION.md
    - specs/00X-<slug>.md
    - releases/  (to see what already shipped)

  SCOPE: T-3 and T-4 only. Do not touch T-5.

  DO NOT: modify acme-web, open a PR, or push.

  CONTEXT THAT CHANGED and is not in older drafts of the spec:
    <...>

  Definition of done: `<command>` green, with output shown.
```
