# Architecture Decision Records

| ID | Decision | Date | Status |
|---|---|---|---|
| ADR-001 | The gateway validates identity; the BFF issues it | 2026-08-29 | Accepted |
| ADR-002 | Agent work lands on a branch and is verified before merge | 2026-08-29 | Accepted |

---

## ADR-001 — The gateway validates identity; the BFF issues it

**Decided** 2026-08-29, while extracting this boilerplate.

### Context

Authentication had to be centralised so that a second back-end — or a public
API for third parties — could be added later without touching the edge. Two
shapes were available: make the gateway a full identity provider with its own
user store, or keep the BFF as the issuer and give the gateway only the
verifying half.

### Decision

The BFF owns users, login, and password reset, and signs access tokens with
**RS256**, publishing its public key at `/api/.well-known/jwks.json`. The
gateway's `auth` service holds no user data: it fetches the JWKS, validates
signature / `exp` / `aud` / `iss`, and injects `X-Auth-*` headers into the
upstream request via Traefik's `forwardAuth`.

### Why

A verifier needs only a public key. That is the whole point: a new back-end
joins by trusting a URL, not by gaining access to the user database. Making the
gateway an identity provider would have meant a second datastore to run, back
up and migrate, and would have thrown away Django's admin, its password-reset
flow and its permission model for no gain at this size.

### Rejected

- **Gateway as IdP** — a second user store to keep consistent with the domain's
  own notion of an account.
- **Shared HS256 secret** — simpler, but every service that verifies can also
  mint. That is exactly the property you do not want when the reason for the
  gateway is to onboard back-ends you trust less than the BFF.

### What would make us revisit

A second back-end that needs to *issue* tokens; or identity moving to an
external provider (Auth0, Keycloak, Cognito), at which point the BFF stops
being the issuer and the gateway keeps doing exactly what it does today.

---

## ADR-002 — Agent work lands on a branch and is verified before merge

**Decided** 2026-08-29, while extracting this boilerplate.

### Context

Agents report their own results. A report is a claim, not evidence.

### Decision

Agent work lands on its own branch. The orchestrator verifies each branch
against the merge — running the suite itself — before integrating. Agents do
not push and do not open PRs.

### Why

Two failure modes, both observed: an agent reporting a green suite it never
ran, and two agents in the same checkout sweeping each other's half-written
files into a commit. A branch plus independent verification catches the first;
`isolation: "worktree"` catches the second.

### Rejected

- **Trusting reported test counts** — cheap right up until it is not.
- **Agents opening their own PRs** — the review gate then has no human in it.

### What would make us revisit

A CI job that runs the same suite on the agent's branch and reports
independently would make the orchestrator's manual verification redundant.

---

> An ADR with no revisit trigger is a rule pretending to be a decision. Every
> entry above ends with one.
