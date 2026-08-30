# acme-gateway

The only thing on this stack with a published port. Two parts:

| Part | What it does |
|---|---|
| `traefik/` | Routing, TLS, rate limits, response headers, scanner blocking |
| `auth/` | A forwardAuth service that verifies tokens and injects identity headers |

## Why a gateway at all

So that a second back-end — or a public API for third parties — can be added
without touching authentication in each one. The verifier holds only a public
key: onboarding a new consumer means trusting a URL, not sharing a secret or
granting access to the user database (ADR-001).

## The request path

```
client ──▶ traefik ──forwardAuth──▶ auth ──JWKS──▶ bff
             │                       │
             │   200 + X-Auth-User-Id / X-Auth-Account-Id / X-Auth-Scopes
             ▼
        upstream (bff or web)
```

Traefik **replaces** the `X-Auth-*` headers with what `auth` returns, so a
client cannot supply its own. The BFF trusts them because it has no published
port and cannot be reached any other way — plus a shared `X-Gateway-Token` so a
compromised container on the edge network cannot forge them either (C-12).

## Two decisions worth knowing about

**No docker provider.** The usual Traefik setup mounts `/var/run/docker.sock`
into the edge container, which hands the most internet-exposed process on the
box the ability to start a privileged container. Routing is declared in files
instead. Adding a service means editing `dynamic/routers.yml`.

**Router priority is load-bearing.** The rules overlap on purpose:
`/api/auth/token` must be caught by the 5/min login limiter before the general
`/api` rule sees it at 120/min. Changing a priority changes which limiter
applies.

## Adding a route

1. Add the router to `dynamic/routers.yml`, with a priority that places it
   correctly against the existing rules.
2. Add the same router to `acme-tf/templates/routers.yml.tftpl`, or production
   will not have it.
3. If it is a new upstream, add the service — and confirm it still has no
   `ports:` in compose.

## Verifying

```bash
./scripts/verify-isolation.sh     # asserts only traefik publishes a port
acme-gateway/auth/.venv/bin/pytest -q
```
