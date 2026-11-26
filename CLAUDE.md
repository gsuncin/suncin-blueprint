# CLAUDE.md

Read this first. It routes you to the rules; it does not restate them. Every
other file is read **by section, when the task reaches it**: reading whole spec
files up front spends the context of every prompt and every subagent on rules
the task never touches.

## Where the work is

**`git log origin/develop` and `releases/` are the truth, not the specs.** A
spec carries the date it was written, not the date the work happened, so a
workstream file describing a task as pending is not evidence that it is.

This is not hypothetical. In the project this template was extracted from, a
session planned and rebuilt a whole wave of work that was already merged,
because `ORCHESTRATION.md` still said "nothing here has been run yet". Every
agent it launched produced a duplicate, and one landed *behind* what the
branch already had.

- `specs/` holds only what is still open; the closed half is in
  [`history/`](history/), with the full text. A spec moves the moment it ships,
  in the same PR as its release note.
- `specs/QUESTIONS.md` is the list of open questions, grouped by who can
  answer. One owned by a human is a hard gate: stop and ask, do not pick a
  default.
- [specs/ORCHESTRATION.md](specs/ORCHESTRATION.md) when you launch or sequence
  agents.

## The Constitution, one line each

All twelve bind every agent. Read the section in
[specs/CONSTITUTION.md](specs/CONSTITUTION.md) for each rule the task touches;
the agent files name theirs. A task that cannot be done without breaking one
needs re-specifying, not a bent rule.

| | Rule |
|---|---|
| C-1 | Integrations never block the domain: return a failure-marked row, do not raise. |
| C-2 | Two orthogonal gates, always both: the plan entitlement and the role permission. |
| C-3 | Provider secrets are encrypted at rest and never leave the BFF, in any form, logs and Sentry included. |
| C-4 | External effects happen once, and idempotently. |
| C-5 | Hexagonal boundaries in the services: no provider vocabulary in `domain/` or `application/`. |
| C-6 | Tenancy is explicit, every time. |
| C-7 | Soft delete, never hard delete. |
| C-8 | TDD, and a green full suite is the exit gate. |
| C-9 | Migrations are additive and reversible in one release. |
| C-10 | Do not fabricate provider behaviour: unconfirmed goes to `specs/research/` as a dated question. |
| C-11 | Fewer, larger, well-named functions; written to be read. |
| C-12 | The gateway is the only ingress. |

## Hard rules

Suggested for every project made from this template; they came from the
orchestrator prompts of the projects it was extracted from, where they were
typed into each session. `scripts/hooks/guard-hard-rules.sh` denies the
commands it can recognise; the rest are yours to keep.

1. **Never merge into `main` and never deploy.** The release merge and the
   deploy are the owner's. `merge-release.sh` without `--merge` prints the
   command for them.
2. **No production writes.** Reads only, through `psql` with
   `PGOPTIONS='-c default_transaction_read_only=on'`.
3. **Real data never leaves the machine and is never committed.** No
   production rows in a fixture, a test, a log line, a PR or a chat.
4. **A client id and client secret live in a file, and you never show their
   values.** Check that a name is set with `grep -c '^NAME=' <file>`; never
   `cat`, echo or paste one.
5. **A login to a provider's test account is always the owner's.** You do not
   type passwords and you do not create accounts.

And one that has cost a token elsewhere: **a token never goes in a URL path or
query string**, which end up in access logs and the browser history. Put it in
a header, or in the URL fragment, which the browser never sends.

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
| nothing; it reviews | `security-agent`, `design-agent` (read-only, on request) |
| `specs/research/` only, and needs the live web | `research-agent` (no Bash, by design) |

**A task that crosses projects belongs to no agent.** Either the orchestrator
does it, or it becomes two tasks with the contract between them fixed before
either starts, in identical words, with instructions to report a mismatch
rather than renegotiate it.

**Brief a subagent with its task section and the `C-n`/`D-n` that bind it,**
never "read everything".

### Which review runs, and when

Reviews run **on request**. If the request did not ask for one, ask the user
once, **at the end of the task**, naming what this table recommends for the
diff; the merge waits for the answer, and the release note records it.

| The diff touches | Recommend |
|---|---|
| a credential, tenancy, the gateway, a public endpoint, a webhook, PII, or a migration | `security-agent` |
| `acme-web/src/**` | `design-agent` |
| a contract between two projects: an env var name, a header, an image name, a service list | a **derived** check, plus reading both ends against each other |
| documentation only | nothing, and say so in the note |

The third row costs the most: each end agrees with itself, the two disagree,
and no suite sees it because each mocks the other. A check that derives the
same fact from both ends does.

How many rounds of bot review a PR gets, and what a finding on a switched-off
path does, is in
[RELEASES → How far the review goes](specs/RELEASES.md#how-far-the-review-goes).

## The flow of a task

1. Read `git log origin/develop`, `releases/`, and the task's section of its
   workstream file.
2. Branch from `origin/develop`, one workstream per branch. In a worktree, run
   `./scripts/worktree-bootstrap.sh` and `source .worktree.env`.
3. Write the failing test first (C-8).
4. Make it pass, smallest change first.
5. Run the suite of every project the diff touches; show the output.
6. Run the derived checks the diff reaches (`check-deploy-contract.sh`,
   `check-doc-links.sh`, `check-ci-skips-drafts.sh`).
7. Commit. A worktree is not storage: commit before you report.
8. Write the release note, `releases/R-YYYY-MM-DD-xxxxxx-<slug>.md`
   ([specs/RELEASES.md](specs/RELEASES.md#the-identifier)), and move the
   shipped spec to `history/` in the same PR.
9. Push and open the PR **into `develop`**, as a draft while it is not ready:
   CI skips drafts, and marking it ready runs everything.
10. Ask the user which reviews to run, per the table above.
11. Clear every review comment: change the code, or reply why not
    ([RELEASES](specs/RELEASES.md#before-you-merge-review-comments-are-a-gate)).
    An unanswered thread blocks the merge.
12. The owner merges `develop` into `main`, a release at a time
    ([RELEASES → the two-branch flow](specs/RELEASES.md#the-two-branch-flow)).
    That merge deploys; nobody else makes it.

## Layout

| Path | What | Stack |
|---|---|---|
| `acme-gateway` | Traefik edge config + `auth` forwardAuth service | YAML, FastAPI |
| `acme-bff` | Domain system of record **and** BFF fronting the services | Django / DRF |
| `acme-svc-example` | Example microservice, **stateless** | FastAPI, ports & adapters |
| `acme-web` | Authenticated SPA + a second Vite entry for the public landing page | React / Vite / MUI |
| `acme-tf` | Terraform, cloud-init, systemd units | Terraform |
| `specs/` | Constitution, workstreams, open questions, research | |
| `releases/` | One release note per merged PR: **the record of what shipped** | |

The services hold **no database**: the BFF owns all state and forwards a live
credential inward per request. **The gateway is the only thing with a
published port**; everything else is reachable by container name on an
internal network (C-12, `docker-compose.yml`).

## Running the suites

The exit gate (C-8). Show the output; a summary line asserting success is not
evidence.

```bash
./scripts/run-all-tests.sh          # everything, stops at the first red
./scripts/verify-like-ci.sh         # what CI runs, the way CI runs it

# or individually:
DEBUG=True DB_NAME=<scratch_db> python acme-bff/manage.py test --parallel
acme-svc-example/.venv/bin/pytest -q
acme-gateway/auth/.venv/bin/pytest -q
npm --prefix acme-web run test:unit     # Vitest
npm --prefix acme-web run test:e2e      # Playwright
npm --prefix acme-web run build         # tsc + vite; type errors surface here
```

Traps that have each cost a debugging session elsewhere:

- `npm run test` does **not** exist. Use `test:unit`.
- `DATABASES["default"]["TEST"]` sets `MIRROR`, so Django uses `DB_NAME`
  directly. Point it at a scratch DB made for the purpose, never your dev
  database, and **`migrate` it first**, or every test errors with
  `relation ... does not exist`. Two worktrees on one scratch DB fight over
  its schema; `worktree-bootstrap.sh` gives each its own, and its own
  `E2E_PORT` so Playwright does not test another worktree's server.
- CI runs the BFF suite with `--parallel`, so a test that passes alone and
  fails beside others is a real failure: it shares state it should not.
- Postgres sorts text by the collation of its C library: glibc in CI and on
  the host, musl in an alpine image. A test that asserts an order of strings
  must sort by an explicit key, not rely on `ORDER BY name`.
- On Linux, Playwright starts the pointer at (0, 0), so a hover style on
  whatever sits top-left is on in the first screenshot. Move the mouse away
  before a visual assertion.

## Secrets

Never commit, log, echo, or paste into a chat: provider API keys, OAuth refresh
tokens, the BFF's JWT signing key, Django `SECRET_KEY`, database passwords,
registry tokens, Terraform state or plan files.

Per-tenant provider credentials are Fernet-encrypted in the database
(`core/crypto.py`), never environment variables. Application-level ones are
environment variables, delivered through Terraform, cloud-init and the
container's env file, never committed.

`*.tfplan` and `*.tfstate*` are gitignored because a plan embeds the whole
state, `user_data` in plaintext included. **Untracking a file does not
unpublish it**: anything ever committed must be rotated, not just removed.

## Working agreements

- **Review comments are a merge gate** (step 11 above).
- **A red suite is information; a fudged green one is a lie.** If a suite
  cannot be made green, the task is blocked, not done: report it with the
  failure output and stop. Never weaken an assertion to accommodate a change;
  decide whether the assertion or the code is wrong, and say which.
- **One agent per project at a time.** Parallelism comes from agents in
  *different* projects.
- **A worktree-isolated agent branches from `develop`, not from your branch.**
  If `develop` is behind, it cannot see your unmerged work. Keep `develop`
  current instead of working around this.
- **Never remove a worktree without looking inside it**
  ([ORCHESTRATION](specs/ORCHESTRATION.md#an-uncommitted-worktree-is-the-most-reliable-way-to-lose-work)).
  A Stop hook blocks on a dirty tree rather than trusting anyone to remember.
- **Discovering an unknown is a successful outcome.** Append it to the
  workstream file with a fresh `Q-n` id rather than guessing past it.
