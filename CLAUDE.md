# CLAUDE.md

Read this first. It routes you to the rules; it does not restate them.

## Before you plan anything, check what actually exists

**Read `git log origin/main` and `releases/` before trusting any spec.** Spec
files carry the date they were written, not the date the work happened. A
workstream file describing a task as pending is not evidence the task is
pending — `releases/` and the git history are.

This is not hypothetical. In the project this boilerplate was extracted from, a
session once planned and rebuilt an entire wave of work that was already
merged, because `ORCHESTRATION.md` still opened with "nothing here has been run
yet" and the specs were dated three weeks earlier. Every agent it launched
produced a duplicate, and one of them landed *behind* what `main` already had.

## Read before writing code

1. **[specs/CONSTITUTION.md](specs/CONSTITUTION.md)** — non-negotiable
   engineering rules (C-1 … C-12). A task that cannot be done without breaking
   one of them needs re-specifying, not a bent rule. The ones that bite most
   often: **C-1** integrations never block the domain (return a failure-marked
   row, do not raise) · **C-3** provider secrets never leave the BFF, in any
   form, including logs and Sentry · **C-8** TDD, and a green full suite is the
   exit gate · **C-11** fewer, larger, well-named functions · **C-12** the
   gateway is the only ingress.
2. **The workstream file for your task**, in `specs/` — checked against
   `releases/` per the section above. `specs/` holds only what is still open;
   the closed half is in [`history/`](history/), a sibling of `releases/`, with
   the full text and nothing summarised. **A spec changes folder the moment it
   ships**, in the same PR as the release note, not as a followup.
3. **[specs/ORCHESTRATION.md](specs/ORCHESTRATION.md)** — if you are launching
   or sequencing agents.

## Which agent does the work

**The directory decides, not the subject.** "It's about billing" tells you
nothing; "it edits `acme-bff/`" tells you everything.

| The work edits | Agent |
|---|---|
| `acme-bff/` | `bff-agent` |
| `acme-web/` | `frontend-agent` |
| `acme-svc-*/`, `acme-gateway/auth/` | `service-agent` |
| `acme-tf/`, `.github/`, `acme-gateway/traefik/` | `infra-agent` |
| tests, anywhere | `qa-agent` |
| nothing — it reviews | `security-agent`, `design-agent` (both read-only) |
| `specs/research/` only, and needs the live web | `research-agent` (no Bash, by design) |

Tools and constraints per agent are in
[ORCHESTRATION → Agent roster](specs/ORCHESTRATION.md#agent-roster).

**A task that crosses projects belongs to no agent.** Either the orchestrator
does it directly, or it becomes two tasks with the contract between them fixed
*before* either starts — in identical words, with instructions to report a
mismatch rather than renegotiate it.

### Which review runs, and when

So nobody has to judge it:

| The diff touches | Run |
|---|---|
| a credential, tenancy, the gateway, a public endpoint, a webhook, PII, or a migration | `security-agent` |
| `acme-web/src/**` | `design-agent` |
| a contract between two projects — an env var name, a header, an image name, a service list | a **derived** check, plus reading both ends against each other |
| documentation only | nothing — and say that in the note, rather than leaving it ambiguous |

**The third row is the one that costs the most.** Each end agrees with itself,
the two disagree with each other, and no suite can see it — because each mocks
the other. A suite cannot be the thing that catches that; a check that derives
the same fact from both ends is.

## Layout

| Path | What | Stack |
|---|---|---|
| `acme-gateway` | Traefik edge config + `auth` forwardAuth service | YAML, FastAPI |
| `acme-bff` | Domain system of record **and** BFF fronting the services | Django / DRF |
| `acme-svc-example` | Example microservice, **stateless** | FastAPI, ports & adapters |
| `acme-web` | Authenticated SPA + a second Vite entry for the public landing page | React / Vite / MUI |
| `acme-tf` | Terraform, cloud-init, systemd units | Terraform |
| `specs/` | Constitution, workstreams, open questions, research | — |
| `releases/` | `R-NNN` release notes, one per merged PR — **the record of what shipped** | — |

The microservices hold **no database**. The BFF owns all state and forwards a
live credential inward per request. Provider vocabulary never appears in a
service's `domain/` or `application/`.

**The gateway is the only thing with a published port.** Every other service is
reachable only by container name on an internal Docker network. That is
structural, not incidental — see C-12 and `docker-compose.yml`.

## Running the suites

These are the exit gate (C-8). Show the output — a summary line asserting
success is not evidence.

```bash
./scripts/run-all-tests.sh          # everything, stops at the first red

# or individually:
DEBUG=True DB_NAME=<scratch_db> python acme-bff/manage.py test
acme-svc-example/.venv/bin/pytest -q
acme-gateway/auth/.venv/bin/pytest -q
npm --prefix acme-web run test:unit     # Vitest
npm --prefix acme-web run test:e2e      # Playwright
npm --prefix acme-web run build         # tsc + vite; type errors surface here
```

Two traps, both of which have cost a debugging session elsewhere:

- `npm run test` does **not** exist. Use `test:unit`.
- `DATABASES["default"]["TEST"]` sets `MIRROR`, so Django uses `DB_NAME`
  directly instead of creating a throwaway test database. Point it at a scratch
  DB you made for the purpose — never your dev database — and **run
  `migrate` against it first**, or every test errors with `relation ... does
  not exist`.

## Secrets

Never commit, log, echo, or paste into a chat: provider API keys, OAuth refresh
tokens, the BFF's JWT signing key, Django `SECRET_KEY`, database passwords,
registry tokens, Terraform state or plan files.

Per-tenant provider credentials are Fernet-encrypted in the database
(`core/crypto.py`), never environment variables. Application-level provider
credentials are environment variables, delivered through Terraform →
cloud-init → the container's env file — never committed.

`*.tfplan` and `*.tfstate*` are gitignored because a plan file embeds the whole
state, including `user_data` in plaintext. **Untracking such a file does not
unpublish it**: anything that was ever committed must be rotated, not just
removed. Everyone who cloned the repo still has it.

## Working agreements

- **Branch from `main`, merge back through a PR, write an `R-NNN` release
  note** ([specs/RELEASES.md](specs/RELEASES.md)). One workstream per PR.
  Numbers are never reused — check `releases/` for the next free one.
  Long-lived accumulation branches strand later work on a stale base.
- **Review comments are a merge gate.** Before merging any PR, read every
  review comment on it and clear each one — either accept it and change the
  code, or resolve it with a reply saying why no change is needed. An open
  thread you have not answered blocks the merge; see
  [specs/RELEASES.md](specs/RELEASES.md#before-you-merge-review-comments-are-a-gate).
- **Branch from `staging`, one workstream per PR; `staging` merges to `main`
  a release at a time.** See
  [RELEASES → the two-branch flow](specs/RELEASES.md#the-two-branch-flow) for
  why, and for what each merge costs. A feature PR still carries everything it
  always did; what changed is where it lands.
- **A worktree is not storage. Commit before you report, and never remove a
  worktree without looking inside it** — see
  [ORCHESTRATION](specs/ORCHESTRATION.md#an-uncommitted-worktree-is-the-most-reliable-way-to-lose-work).
  A Stop hook blocks on a dirty tree rather than trusting anyone to remember.
- **A red suite is information; a fudged green one is a lie.** If a suite
  cannot be made green, the task is blocked, not done. Report it with the
  failure output and stop. Never weaken an assertion to accommodate a change —
  if a merge makes an assertion fail, decide whether the assertion or the code
  is wrong, and say which.
- **One agent per project at a time.** Parallelism comes from agents working in
  *different* projects. Two agents in `acme-bff` will conflict.
- **A worktree-isolated agent branches from `staging`, not from your branch.**
  If `staging` is behind, the agent cannot see your unmerged work, and a prompt
  written against your branch describes a repository it is not looking at. Keep
  `main` current instead of working around this.
- **Do not fabricate provider behaviour** (C-10). A field name, limit, or
  webhook shape that is not confirmed against live docs or a sandbox call goes
  into `specs/research/` as a dated open question — not into a spec as fact,
  and not into code without a comment saying it is unverified.
- **A red suite is information; a fudged green one is a lie.** If a suite
  cannot be made green, the task is blocked, not done. Report it with the
  failure output and stop. Never weaken an assertion to accommodate a change —
  if a merge makes an assertion fail, decide whether the assertion or the code
  is wrong, and say which.
- **Discovering an unknown is a successful outcome.** Append it to the
  workstream file with a fresh `Q-n` id rather than guessing past it.

## Open questions and decisions

`specs/QUESTIONS.md` is the consolidated list, grouped by who can answer.
Resolved questions move back into their workstream file with the answer and a
date. Anything owned by a human is a hard gate — stop and ask, do not pick a
default.
