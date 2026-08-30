# R-001 — The boilerplate itself

**Date:** 2026-08-29
**Workstream:** WS-000 (bootstrap) · **Tasks:** all
**Status:** merged

---

## Implemented

A monorepo that runs and has a green suite before any domain code is written.

### The gateway is the only ingress

Three named Docker networks replace the single implicit bridge: `edge`
(traefik, web, bff, auth), `services` (bff, worker, svc-example) and `data`
(postgres, rabbitmq, bff, worker) with `internal: true`.

`services` is a plain bridge rather than internal, deliberately — a provider
adapter has to reach its provider. What closes it off is that nothing there
publishes a port, nothing there has a Traefik router, and the firewall opens
80/443 only.

`scripts/verify-isolation.sh` asserts all of it and runs in CI. The Terraform
render tests assert the same thing against the production compose file, so a
second published port cannot reach a box.

### Identity: the BFF issues, the gateway verifies

Django signs RS256 and publishes a JWKS endpoint with an RFC 7638 thumbprint
`kid`. The gateway's `auth` service holds no key material and cannot mint a
token — it fetches the JWKS, validates signature/exp/aud/iss, and injects
`X-Auth-*` headers that Traefik substitutes for anything the client sent.

An unknown `kid` forces a refetch, rate-limited so a flood of forged tokens
cannot become a denial of service against the issuer. A stale cache keeps
serving through a brief issuer outage.

### A hexagon that is a template, not an example

`acme-svc-example` has two real adapters — a deterministic mock and an HTTP one
— behind one port, and a parametrised contract suite that both must pass
unmodified. Verdicts return HTTP 200; only auth, validation and bugs are 4xx.

### The frontend

Two Vite entries from one image, chosen by `Host`. TanStack Query over
per-endpoint service functions. Three gates mirroring the backend. Access token
in memory, refresh token in an HttpOnly cookie, single-flight refresh. A
landing page with a byte budget enforced against a real build, a Lighthouse
floor, and a `<noscript>` fallback.

## TDD coverage

```
svc-example (pytest)      48 passed
gateway auth (pytest)     20 passed
bff (django)              Ran 71 tests — OK
web unit (vitest)         20 passed (6 files)
web e2e (playwright)      12 passed
terraform render tests    3 passed
                          ---
                          174
```

Mutation-tested rather than assumed. Each of these was deliberately broken and
the suite caught it: removing the tenancy filter (2 failures), dropping the
service-layer entitlement check (1), removing the idempotency guard (2),
trusting a client-supplied account (1), mapping an unknown provider status to
ERROR (1), removing credential scrubbing (1), letting an unexpected provider
error propagate (2), and publishing a port on the microservice (1 Terraform
assertion).

## Backend

Django 5.2 / DRF. Settings split by concern. `core/service_client.py` is the one
chokepoint for outbound calls — timeout, typed error, mandatory audit argument,
no retry loop. `example/` is the reference app shape.

## Frontend

React 19 / Vite 8 / MUI 9 / TanStack Query 5. Route-level code splitting,
ESLint flat config, Prettier, light and dark colour schemes.

## Infrastructure

Terraform module rendering cloud-init, the compose file and the Traefik
routers, with an OCI reference environment and an `existing-host` environment
for any other provider. systemd units, nightly backups with checksums,
fail2ban over the Traefik access log, ufw, unattended upgrades.

Fourteen GitHub Actions workflows: four `workflow_call`-only test suites, four
image builds gated on them, Terraform checks including the render tests and
`tfsec`, an isolation check, deploy with rollback and a public smoke test, a
read-only diagnose workflow, release notes and the review gate.

## Also changed

Three defects found by building the thing rather than by reading it:

1. **`SIMPLE_JWT["VERIFYING_KEY"]` was never derived**, so RS256 refresh failed
   at runtime. Now derived from the private key at startup — one secret to
   rotate rather than a pair that can drift.
2. **`_live_credential` read a model field that did not exist.** The suite ran
   only the unconfigured-key branch, so it was green while the first real
   request raised `AttributeError`. Fixed, and the configured-key path now has
   tests, including one asserting the ciphertext never reaches an API response.
3. **`python-decouple` walks up the tree for `.env`**, so `manage.py test` was
   being configured by the repo-root file that `docker compose` uses. Whether a
   test passed depended on whether someone had run `make keys`.
   `core/settings/env.py` pins the lookup to one path.

Two more, found by running `init-project.sh` on a copy: the test runner never
created the DRF cache table, and never ran `terraform init` — both of which
only worked on a machine where someone had done it by hand.

## Spec deltas

`specs/CONSTITUTION.md` gains **C-12 — the gateway is the only ingress**.
`specs/DECISIONS.md` records ADR-001 (the BFF issues, the gateway verifies) and
ADR-002 (agent work is verified before merge).

## A note for the constitution

The `replace(secret, "$", "$$")` idiom before `templatefile` — inherited from
the project this was extracted from, and widespread in published Terraform — is
a bug. Measured on Terraform 1.14: a 7-character secret containing `$` comes
back 7 characters without it and **9 with**. `templatefile` does not
re-interpolate substituted values, so the escaping corrupts rather than
protects, and the symptom is an authentication failure on a freshly
provisioned box.

Removed here, with the measurement recorded in `acme-tf/README.md`. Worth
checking anywhere else the pattern was copied to.

## Migration notes

`none` — this is the first release.
