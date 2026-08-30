---
name: project-context
description: Use when working on any part of this monorepo and you need the shared world-model — what actually ships today, what is only scaffolding, how the pieces talk to each other, and which vocabulary is real.
---

# Project context

**Last verified against the codebase: 2026-08-29** — the day it was built,
with all 174 tests green.
**If something here disagrees with the code, the code wins — and fix this
file.** A stale version of a file like this one has caused a whole wave of
agents to be launched against wrong context.

## Layout

| Path | What | Stack |
|---|---|---|
| `acme-gateway` | Traefik edge + `auth` forwardAuth service | YAML, FastAPI |
| `acme-bff` | System of record and BFF; issues identity tokens | Django 5.2 / DRF 3.16 |
| `acme-svc-example` | Example stateless microservice | FastAPI, ports & adapters |
| `acme-web` | Authenticated SPA + public landing entry | React 19 / Vite 8 / MUI 9 / TanStack Query 5 |
| `acme-tf` | Terraform, cloud-init, systemd | Terraform |

## What actually ships today

This is a **boilerplate**. Nothing here is a product feature; every item below
exists to demonstrate a shape that real work will replace.

| Area | Shipped | Not built |
|---|---|---|
| Identity | Email login, RS256 access token, HttpOnly refresh cookie, JWKS endpoint | Signup, SSO, MFA |
| Authorization | Role → capability matrix, plan entitlement gate, both enforced | Any real role beyond the four examples |
| Gateway | Traefik routing, forwardAuth, rate limits, security headers, ACME | Public third-party API clients |
| Microservice | One hexagon with two adapters (`mock`, `example`) and a contract suite | Any real provider |
| BFF → service | JWT-authenticated client with audit, timeout, failure-marked rows | Retry sweeps for a real workload |
| Async | Celery worker + beat, one example scheduled task | Any real job |
| Frontend | Two Vite entries, three route gates, TanStack Query, theme with dark mode | Any real page |
| Infra | Terraform module + OCI env + existing-host env, cloud-init, backup, fail2ban | A second host, blue/green |

## How the pieces talk

```
browser ──▶ traefik ──forwardAuth──▶ auth-svc ──JWKS──▶ bff
             │                        │
             │  X-Auth-User-Id, X-Auth-Account-Id, X-Auth-Scopes
             ▼
            bff ──JWT(HS256, 60s, iss+aud)──▶ svc-example
                 └── X-Provider-Credential header, never a body
```

- The **BFF is the only stateful party**. Services hold no database and get a
  live credential per request.
- A **provider webhook does not reach a service**. It hits the BFF on a public
  route; the BFF relays it inward.
- The **gateway is the only container with a published port** (C-12).

## Vocabulary

- **Account** — the tenant. Every row that belongs to a customer has
  `account_id`.
- **Entitlement** — what the Account's *plan* allows. No actor.
- **Capability** — what a *user's role* allows: `view` or `manage` on a
  `ResourceArea`.
- **Verdict** — a provider's answer. Returned as HTTP 200 with a status in the
  body, never as an error code.

## Implementation guidance

Read `specs/CONSTITUTION.md` first. When adding anything, find the existing
example of its shape and copy that: `example/` in the BFF, `say_hello` in the
service, `components/<Name>/index.tsx` in the web app. The boilerplate exists
so that the answer to "how do I do X here" is always "like the one next to it".
