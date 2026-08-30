# Engineering Constitution

Non-negotiable rules. Every agent working in this monorepo loads this file
before touching code. A task that cannot be completed without breaking one of
these rules is a task that needs re-specifying, not a rule to bend.

## C-1 — Integrations never block the domain

Anything that leaves the process — charging a card, emitting a document,
syncing an external calendar, sending a message — is a *side effect of* the
domain operation, never a precondition for it. The record gets created and the
work gets done regardless of whether any provider is reachable.

Concretely: service functions in these paths **return a failure-marked row,
they do not raise**. `acme-bff/example/services.py` is the reference
implementation — `create_example_job` catches everything and writes
`error_code` / `error_message` onto the row.

```python
def create_example_job(record):
    """Never raises. On any failure the row comes back with status=ERROR and a
    machine-readable error_code the caller can branch on."""
    try:
        return _attempt(record)
    except ServiceError as exc:
        return _fail(record, "SERVICE_UNREACHABLE", str(exc))
    except Exception as exc:
        logger.exception("Unexpected error for record %s", record.id)
        return _fail(record, "UNEXPECTED_ERROR", str(exc))
```

Every gate and precondition returns through that same `_fail` helper with a
*distinct* `error_code`, so the caller can tell "your plan does not include
this" from "the provider timed out". `_fail` redacts before it writes and uses
`save(update_fields=[...])`, so it cannot blank a column a concurrent webhook
just set.

## C-2 — Two orthogonal gates, always both

- **Entitlement** (`accounts/entitlements.py`) answers *"is this Account's plan
  allowed to do this at all?"* — no actor involved, so headless Celery paths
  reach the same verdict as an HTTP request.
- **Role permission** (`users/permissions.py`) answers *"may this user, inside
  a paying account, act?"*

Never collapse them into one check. A plan denial must be able to say "your
plan does not include this" instead of "you have no permission". Any new gated
capability adds an `Entitlement` constant **and** picks a `ResourceArea`.

The DRF permission class cannot see headless paths, so the entitlement check is
repeated inside the service layer. That duplication is deliberate.

## C-3 — Provider secrets are encrypted at rest and never leave the BFF

Provider API keys, OAuth refresh tokens, and certificate passwords are
Fernet-encrypted (`core/crypto.py`) and **never** appear in:

- API responses or serializers (even for staff)
- the Django admin, in any form
- logs, exception messages, or Sentry breadcrumbs
- the audit log — which redacts before it writes, not after

The microservices stay **stateless**: credentials travel inward per-request in
a **header**, never in a body or query string, and are never persisted
service-side. The audit recorder logs request payloads and never headers, which
is what makes that split load-bearing rather than stylistic.

A composition root that fails for missing configuration lists the *names* of
the missing settings, never their values.

## C-4 — External effects happen once, and idempotently

Every path that settles an external effect must be safe to replay. Providers
deliver webhooks out of order, duplicate them, and lose them. The invariants:

- A nullable foreign key to the resulting record is the idempotency key — a
  replayed webhook finds it set and creates no second record.
- Settlement takes `select_for_update()` before writing, and **re-checks the
  condition inside the lock**.
- A settled record cannot be un-settled by a stale event; only genuinely later
  facts get through.
- A polling sweep exists as the safety net for webhooks that never arrive.

Any new provider adapter inherits these. No exceptions, no "this provider is
reliable".

## C-5 — Hexagonal boundaries in the microservices

Each microservice is ports & adapters. The domain and the driving API are
**provider-agnostic**; concrete providers plug in behind ports.

- Adding a provider must not touch a use case (OCP). If it does, the port is
  wrong — fix the port. Apply that test to your own diff.
- Provider vocabulary never leaks into `domain/` or `application/`. It lives
  only under `adapters/driven/providers/<name>/`.
- Wire format is camelCase; Python stays snake_case. `schemas/base.py`
  `CamelModel` is the only place that knows.
- Domain models are `frozen=True`.
- **Verdicts return HTTP 200.** A provider rejecting a request is a fact about
  the world, not a bug in the caller. 4xx/5xx are reserved for auth,
  validation, and bugs.
- The composition root is eager: a box configured for a provider this build
  cannot serve fails at startup, not on the first real request.

## C-6 — Tenancy is explicit, every time

Every new queryset filters by `account_id` for non-staff users. There is no
implicit tenant middleware to rely on. Use `core/mixins.py`
`TenantQuerysetMixin`; do not invent a second one.

## C-7 — Soft delete, never hard delete

`is_active=False` + `inactive_at`. All querysets filter `is_active=True`.
`perform_destroy` deactivates and `destroy()` returns 200 with the serialized
row, so the client can show what it just archived.

## C-8 — TDD, and a green suite is the exit gate

**Tests come first, and no task is complete until the full suite passes.**
This is a hard gate, not a preference.

### Write the test first

For every main functionality — the behaviour a task exists to deliver — the
test is written **before** the implementation:

1. Write a test that expresses the required behaviour.
2. Run it. **Watch it fail.** A test that has never failed has proven nothing;
   it may be asserting something already true, or asserting nothing at all.
3. Implement until it passes.
4. Consolidate (C-11) with the test as the safety net.

"Main functionality" means the behaviour named in the task's Definition of
Done. Incidental plumbing — a settings constant, a `__str__`, a field label —
does not need a test written first. When in doubt, write it first; the cost is
minutes.

### Required coverage

| Change | Required coverage |
|---|---|
| Provider adapter | `respx`-mocked tests (happy path, provider error, timeout, malformed payload) + the shared contract suite |
| BFF service function | Unit test incl. the failure path (C-1) |
| API endpoint | DRF test covering tenancy (C-6) and both gates (C-2) |
| Settlement/idempotency | A replay test asserting exactly one resulting record |
| Celery task | A test that the task is enqueued, and one that the domain survives it failing |
| Migration | A test that data survives it, when it backfills or changes meaning |
| Gateway routing/auth | A test that the route is unreachable without a valid token |
| Frontend component | Vitest + RTL; `getByRole`, not `getByLabelText`, on MUI selects |
| Frontend route | Playwright smoke; anchor API mock regexes to the path start |

### The exit gate

**An agent may not report a task complete unless it has run the full relevant
suite and every test passed.** Not "the tests I wrote pass" — the whole suite
for the project it touched:

```bash
./scripts/run-all-tests.sh
```

`DATABASES["default"]["TEST"]` sets `MIRROR`, so Django does **not** create a
throwaway test database — it uses `DB_NAME` directly. Point it at a scratch
database you created for the purpose, never at your dev database.

**And because it is a mirror, `TransactionTestCase._fixture_teardown` excludes
it from the flush.** A `TransactionTestCase` therefore **leaks its rows into
the scratch database**, breaking later tests in the same run *and every
subsequent run* until the database is recreated. Any `TransactionTestCase` in
this project must clean up after itself explicitly, with a comment saying why.
Found the hard way elsewhere: one two-thread concurrency test broke 69
unrelated tests across two consecutive runs.

The agent must **show the output**. A summary line asserting success is not
evidence; the printed result is.

If a suite cannot be made green, the task is **blocked, not done**. Report it
that way, with the failure output, and stop. Deleting, skipping, or weakening
an assertion to reach green is a worse outcome than a red suite honestly
reported — a red suite is information, a fudged green one is a lie the next
agent will build on.

This gate also applies to a task that only *touches* code it did not write. If
your change broke someone else's test, that is your task's problem now.

## C-9 — Migrations are additive and reversible in one release

No column drops in the same release that stops writing them. Rename = add new,
backfill, dual-write, cut reads, drop later. The production box has one
database and no blue/green.

## C-10 — Do not fabricate provider behaviour

If a provider's limit, field name, or webhook shape is not confirmed against
either the live docs or a sandbox call, it goes in `specs/research/` as an
**open question with a date**, not into a spec as fact. An honest "unverified
against a live account" note is exactly what makes an adapter cheap to replace
later — keep that standard.

## C-11 — Write code to be read, not to be decomposed

**Project-wide rule, every project, new code and refactors alike.**

Optimise for someone opening the file cold and understanding it top to bottom.
That usually means **fewer, larger, well-named functions** — not a cloud of
tiny private helpers each doing one line of work.

**Do not** extract a helper whose body is a single expression or a single
attribute access:

```python
# NO — pulverised. Four indirections to read one payload.
def _get_payer_name_from_payload(p): return p["payer"]["name"]
def _get_payer_doc_from_payload(p): return p["payer"]["document"]
def _as_decimal(v): return Decimal(str(v)) if v is not None else Decimal("0")
def _parse_dt(v): return parse_datetime(v) if v else None
```

**Do** extract when the helper carries a *concept* the caller should not have
to hold in its head — a whole payload build, a whole validation pass, a whole
state transition:

```python
# YES — one function per meaningful step, each readable on its own.
def build_request_payload(record, config): ...
def apply_provider_result(record, result): ...
```

### The test

Before extracting, ask: **does the name save the reader more than the jump
costs them?** `_get_text_a_from_payload` does not — inline it. `_build_payload`
does — keep it.

A second signal: if a helper is called exactly once, from one place, and its
body is under ~3 lines, it is probably a comment pretending to be a function.
Write the comment.

### SOLID, applied with judgement

Single responsibility means a *function does one job*, not that a job must be
split until each piece is trivial. Open/closed still binds the provider
adapters (C-5) — that abstraction earns its keep because it has a real second
implementation. Do not add an interface for a thing with one implementation
and no concrete plan for a second.

Naming carries the weight that decomposition used to: a long, specific,
unambiguous function name is better than a short name plus three helpers
explaining it.

### In test code too

Some duplication between tests is cheaper than indirection. A test that needs
three lines of setup read inline is better than one that needs you to go find
a fixture to know what it asserts.

## C-12 — The gateway is the only ingress

**Exactly one container publishes a host port: the gateway.** Everything else
is reachable only by container name on a Docker network. This is verified, not
assumed — `scripts/verify-isolation.sh` asserts it, and it runs in CI.

- A new service gets `expose:`, never `ports:`. If you think you need a host
  port, you want a gateway router.
- Datastores live on the `data` network, which is `internal: true` — no
  gateway, no route in or out.
- **A service trusts an identity header only because it cannot be reached
  except through the gateway.** The gateway strips any inbound `X-Auth-*` from
  the client and re-injects its own, and adds a shared `X-Gateway-Token` so a
  compromised container on the edge network cannot forge identity either.
- A provider webhook does not reach a microservice directly. It hits the BFF on
  a public route, and the BFF relays it inward — the service is stateless and
  could not act on the event on its own.

Widening this is a specification change, not an implementation detail.
