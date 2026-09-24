# R-2026-09-24-5b75bf — the hardening from the first project built on this template

**Status:** merged
**Branch:** `feat/port-hardening`

Everything here was learned in the first project built on this boilerplate and
carried back. Nothing is speculative: each item is a defect that shipped there,
generalised so the template cannot repeat it.

## Implemented

**"Derive, don't list."** Five files named their subjects by hand, so a stack
that grows a service grows a silent gap — a loop over a list that does not
mention a service cannot fail on it. `svc-tests.yml` now discovers
`acme-svc-*/` into a matrix, `run-all-tests.sh` and `verify-isolation.sh`
loop, and `deploy-remote.sh` derives one list from the image lines its own
pinning `sed` rewrites. `check-deploy-contract.sh` derives the same set from
two independent sources and fails when they disagree, with a negative control
proving the derivation reads the file it is handed.

**Five Claude Code hooks.** A rule that is written down and still broken needs
a hook, not another sentence: the Django working directory, AI attribution on a
commit, broken relative links, a dirty tree at Stop, and committed work with no
PR.

**Object storage.** MinIO in both compose files, on the internal `data`
network, from quay.io — `minio/minio` no longer exists on Docker Hub, the
repository 404s — with an `mc ready local` healthcheck, because curl is not in
the image.

**A release identifier that cannot collide.** `R-YYYY-MM-DD-xxxxxx` replaces
`R-NNN`: a number read at write time is claimed at merge time, and two
branches both writing `R-064-<own slug>.md` merge without a conflict.

**The gateway invariant.** Every Traefik chain either authenticates or strips
the client-supplied identity headers, with no exception, and
`verify-isolation.sh` check 4b fails the build on any chain that has neither.

## Defects found and fixed on the way

Each was latent in the template before this branch:

1. `deploy-remote.sh`'s hardcoded list omitted `worker`, so a rollback left
   the worker on the image the release had just proved broken.
2. CI publishes `acme-gateway-auth`; the tfvars example told the box to pull
   `acme-auth` — `docker compose pull` 404s on every deploy filled in from it.
3. `precommit-changelog-docs.sh` passed a multi-line value through `awk -v`,
   an error on BSD awk, so the hook aborted every commit on macOS.
4. `make test-bff` invoked the Django runner from the repo root, where it
   discovers nothing and exits `Ran 0 tests ... OK`.
5. `make test-svc` named one service and did not `cd`; pytest from the root
   fails collection.
6. The `.claude` permission list pre-approved the same broken Django spelling.
7. `api-health` carried no middleware at all — no rate limit, no strip, on the
   one route a stranger can call unauthenticated.
8. The render fixture rendered `example.test/...`, invisible to any derivation
   keyed on the registry host.

## TDD coverage

`find-release-note.test.sh`: **41 assertions, 0 failed** — both identifier
formats, the workflow's trigger list read out of the workflow, and every note
in `releases/` held to the round trip.

## Backend

`rehearse_integrations` calls every function `integrations/` exports for
real, deriving the list from each client module's `__all__` — which is what
covers the function with no caller, the one most likely to be wrong. This is
the only thing in the repo that crosses the BFF→service boundary for real.

## Frontend

None.

## Infrastructure

MinIO in the module, its variables threaded through both environments and the
render fixture; `compose_file` exposed as a module output so shell-level checks
read the same text that lands on the box; `deploy-contract.yml` and
`doc-links.yml` added.

## Also changed

`design-agent` added (read-only, `acme-web/src`). The five writing agents
carry `isolation: worktree`. CLAUDE.md gains the directory-to-agent routing
table and the matrix of which review runs when.

## Spec deltas

- `RELEASES.md` — the identifier, the two-branch flow, what a merge requires.
- `specs/README.md` — `specs/` vs `history/`, the three rungs before filing
  a `Q-n`, and that a `Q-n` id is not a question.
- `ORCHESTRATION.md` — the worktree rule, keeping `develop` current,
  `design-agent` in the roster.
- `history/` created, with its README.

## Migration notes

**Adopters must create a `develop` branch** for the two-branch flow.
`require-pr-on-stop.sh` detects its base rather than assuming one, so a
repository without `develop` is not blocked — it falls back to the remote's
default branch.

`make keys` now generates `STORAGE_ACCESS_KEY` and `STORAGE_SECRET_KEY`. An
existing `.env` gets them appended on the next run; the BFF refuses to start
without the four required `STORAGE_*` when `DEBUG` is off, which is the
intended behaviour and not a regression.

## Deliberately left out

- `spec-board-sync.yml` — it requires a GitHub Projects board and the
  `NN-*.md` queue, neither of which the template prescribes.
- The domain code, and the `acme-svc-example` / `example/` scaffolding stays:
  the template's job is to show the shape, not to ship a product.
