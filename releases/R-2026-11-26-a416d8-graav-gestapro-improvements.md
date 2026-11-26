# R-2026-11-26-a416d8 — what graav-app and gestapro-monorepo learned since the template

**Status:** open
**Branch:** `chore/port-graav-gestapro-improvements`

Ported from the two projects built on this template before a third one starts
from it, so it does not relearn the same lessons. Each item is something that
shipped there; the graav- or gestapro-specific parts (environments, service
names, providers) were left behind and only the pattern came across.

## Implemented

**CI that costs less and proves more.**
- A draft PR runs nothing, and marking it ready runs everything;
  `check-ci-skips-drafts.sh` fails on a pull-request workflow that forgets.
- A tree that already passed is not tested twice: `tested-tree.sh` publishes a
  commit status per suite, keyed on the tree, and the release merge's push to
  `main` skips the suites that tree already passed.
- Django runs with `--parallel` and Playwright against the production build.

**A deploy that fails before it touches the box.**
- `deploy-prod.yml` runs from `workflow_run`, only after every image build
  for a push to `main` succeeded.
- It checks every image exists first; `retag-unchanged.yml` re-tags images
  whose paths did not change, instead of rebuilding them.
- `deploy-remote.sh` validates the tag, stages `docker-compose.next.yml` and
  pulls from it before moving it into place, keeps
  `docker-compose.previous.yml`, and rolls back to the refs the containers
  were actually running.

**The gateway.**
- `ratelimit-app` is 120/60, so a team behind one NAT is not throttled as one
  user.
- The anonymous surface gets `ratelimit-public` (20/10) and a
  `public-anon-chain` on a new `api-public` router.

**CSP report-only.** A `Content-Security-Policy-Report-Only` header sits beside
the enforced one and reports to `/api/public/csp-report/`. That endpoint:
- is throttled;
- takes at most 4 KB;
- logs only the directive, the blocked origin and the page's origin plus its
  first path segment, so a report cannot carry a token or an id into the logs.

**The AI harness.**
- `CLAUDE.md` carries the Constitution one line each. Agents read the section
  of each rule their task touches, not whole files.
- `security-agent` and `design-agent` run on request: the orchestrator asks
  the user at the end of the task.
- Bot review is limited to two rounds per feature PR, and a finding on a
  switched-off path becomes an Issue (gestapro R-409).
- A **Hard rules** section, marked as suggested, comes with
  `guard-hard-rules.sh`, which denies:
  - pushing or merging into `main`;
  - deploying;
  - a production `psql` that is not read-only;
  - printing a secret file.
- `worktree-bootstrap.sh` gives each worktree its own scratch database, e2e
  port and venvs.

## Defects found and fixed on the way

Each was latent in the template before this branch:

1. `user-data` wrote `$$(...)` and `$${VAR}` where `templatefile` only
   unescapes `$${`. The backup script and first boot therefore ran bash's
   `$$` (its PID) followed by literal text, and the nightly dump went to a
   file named after a number.
2. The worker healthcheck rendered `$$$$HOSTNAME` and checked a node name that
   never exists, so the worker was never healthy.
3. `docker-svc.yml` built `acme-svc-example` by name, so a second service was
   never published.
4. `CLAUDE.md` said both "branch from `main`" and "branch from `develop`",
   still named the retired `R-NNN`, and listed one working agreement twice.

## TDD coverage

| Check | Result |
|---|---|
| `scripts/tests/tested-tree.test.sh` | 72 passed |
| `scripts/tests/merge-release.test.sh` | 24 passed |
| `scripts/tests/retag-unchanged.test.sh` | 127 passed |
| `scripts/tests/guard-hard-rules.test.sh` | 27 passed (both directions) |
| `scripts/tests/gateway-rate-limits.test.sh`, `gateway-csp.test.sh` | pass; CSP negative control fails as it should |
| BFF suite | 71 OK, serial and `--parallel`; `core/tests_csp_report.py` 9 new |
| `terraform test` (render) | 3 passed, with the new `no_doubled_shell_dollar` assertion |
| `check-deploy-contract.sh` | PASS; section 6 negative control fails as it should |
| `check-ci-skips-drafts.sh` | 8 workflows ok |
| actionlint, `terraform fmt` | clean |

Not run here: the docker-dependent checks of `verify-isolation.sh` and the
Playwright suite, for want of a docker daemon. Its static checks 4 and 4b pass.

## Infrastructure

- `backup_upload_url` (sensitive, default `""`): when it is set, the nightly
  dump is also uploaded off the box.
- `acme-tf/docs/deploy.md` covers:
  - the preflight;
  - the staged compose file;
  - the env contract, which the migration step already enforces;
  - why the deploy key deserves a restricted user of its own.

## Spec deltas

- `CONSTITUTION.md`: section-by-section reading.
- `ORCHESTRATION.md`:
  - `origin/develop`;
  - rule 4 is now "on request, before merge";
  - new rule 6 on briefing a subagent.
- `RELEASES.md`:
  - merge requirement 2 is now "reviews asked for or approved";
  - new section "How far the review goes";
  - the identifier is `R-YYYY-MM-DD-xxxxxx` throughout.

## Migration notes

A project already made from the template takes the `user-data` and compose
template fixes by re-rendering. The backup script is written by cloud-init at
first boot, so a box that is already running keeps the broken one. Fix it by
re-provisioning the box, or by patching `/usr/local/bin/<project>-backup.sh` by hand with
the rendered version.

Reviews: none run. Infrastructure, gateway and a public endpoint are touched,
so `security-agent` was recommended; the owner approved merging into `develop`
without it on 2026-11-26.
