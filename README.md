# Monorepo boilerplate

A gateway, a BFF, a stateless microservice, a two-entry frontend, and the
Terraform that deploys them to one Ubuntu VPS. It runs, and its suite is green,
before you write a line of your own code.

```bash
./scripts/init-project.sh my-app "My App"
make up
```

Then open http://app.localhost and sign in as `dev@acme.test` /
`acme-dev-password`.

`make test` needs one thing `make up` does not: a Postgres on the host. It is a
one-time setup — see [Running the suites](#running-the-suites).

## What is here

| Path | What | Stack |
|---|---|---|
| `acme-gateway` | Traefik edge + a forwardAuth service that verifies tokens | YAML, FastAPI |
| `acme-bff` | System of record and BFF. Issues identity, owns all state | Django / DRF |
| `acme-svc-example` | Example stateless microservice, ports & adapters | FastAPI |
| `acme-web` | Authenticated SPA + a public landing page, two Vite entries | React / Vite / MUI |
| `acme-tf` | Terraform, cloud-init, systemd, backups | Terraform |
| `specs/` | The constitution, workstream template, decision log | — |
| `releases/` | `R-NNN` notes — the record of what shipped | — |

## The shape

```
              internet — 80/443 only. Port 22 is not open; SSH is on the tailnet.
                              │
                      ┌───────▼────────┐
                      │    traefik     │  the ONLY container with a published port
                      └───────┬────────┘
         ┌───────────────────┼──────────────────────┐
         │ forwardAuth       │                      │
    ┌────▼─────┐       ┌─────▼─────┐          ┌─────▼──────┐    edge
    │   auth   │       │    web    │          │    bff     │
    │ verifies │◄──────│ SPA+land. │          │  issues    │
    │  (JWKS)  │       └───────────┘          └─────┬──────┘
    └──────────┘                                    │        services
                                      ┌─────────────┴──────────────┐
                                 ┌────▼─────────┐          ┌───────▼──────┐
                                 │ svc-example  │          │    worker    │
                                 └──────────────┘          └───────┬──────┘
                                                                   │  data (internal)
                                           ┌───────────────────────┴────────┐
                                     ┌─────▼─────┐                  ┌───────▼────┐
                                     │ postgres  │                  │  rabbitmq  │
                                     └───────────┘                  └────────────┘
```

**The gateway is the only ingress.** Every other service is reachable only by
container name on a Docker network. That is checked, not asserted:

```bash
make verify
```

## Prerequisites

Docker, Node 22+, Python 3.11+, Terraform 1.5+.

`make up` needs nothing else. **`make test` also needs a Postgres running on
the host**, reachable at `127.0.0.1:5432`. The stack's own Postgres cannot
serve it: that container publishes no host port, and `make verify` fails the
day one is added — in the running stack *and* in `docker-compose.yml`. The
suites run outside Docker, so they need a database outside Docker.

## Commands

```bash
make help      # everything below, with descriptions
make up        # build, start, migrate, seed
make test      # every suite, stopping at the first red
make verify    # assert the gateway is the only ingress
make logs S=bff
make down
```

## Running the suites

`make test` is the exit gate. It runs, in order: the microservice pytest suite,
the gateway auth suite, Django migrations and tests, frontend lint, build, unit
and e2e, then Terraform format and render tests.

Once per machine, create the scratch database the Django suite runs against:

```bash
createdb -h 127.0.0.1 -U acme acme_scratch
```

Without it the run stops at the first Django step with `database
"acme_scratch" does not exist`. The defaults assume a role `acme` that can
connect without a password; point them somewhere else with the environment:

```bash
SCRATCH_DB=my_scratch DB_USER=me DB_PASSWORD=secret make test
```

`DB_HOST`, `DB_PORT`, `DB_USER` and `DB_PASSWORD` reach the runner directly.
The database name is `SCRATCH_DB`, not `DB_NAME` — the `make test` recipe sets
`DB_NAME` itself, so setting it in the environment has no effect.

Two traps worth knowing before they cost you an afternoon:

- **`npm run test` does not exist.** It is `test:unit`.
- **Django's test database is a `MIRROR`**, so the runner uses `DB_NAME`
  directly instead of creating a throwaway. Point it at a scratch database you
  made for the purpose — never your dev data — and migrate it first.

## Authentication

The BFF issues; the gateway verifies. The BFF signs access tokens with RS256
and publishes its public key at `/api/.well-known/jwks.json`. The gateway's
`auth` service fetches that key, validates each request, and injects
`X-Auth-User-Id` / `X-Auth-Account-Id` / `X-Auth-Scopes` into the upstream
request — replacing whatever the client sent.

A verifier that holds only a public key cannot mint tokens. That is what lets a
second back-end join later by trusting a URL, rather than by being handed a
secret or access to the user database. See
[specs/DECISIONS.md](specs/DECISIONS.md) ADR-001.

The refresh token never reaches JavaScript: it lives in an HttpOnly cookie, and
the access token is kept in memory only.

## Deploying

```bash
cd acme-tf/envs/oci
cp terraform.tfvars.example terraform.tfvars   # fill it in
set -a; source .env; set +a                    # secrets as TF_VAR_*
terraform init && terraform apply
```

`envs/existing-host` does the same against a VPS you already have, on any
provider. Both render the same stack from `modules/app-stack`.

Deploys after the first are `.github/workflows/deploy-prod.yml`: it joins the
tailnet, streams `.github/scripts/deploy-remote.sh` to the box, migrates, swaps
containers, waits for health, and rolls back if they do not come up.

## Before you start writing

Read **[specs/CONSTITUTION.md](specs/CONSTITUTION.md)**. It is twelve rules,
each of which exists because breaking it cost someone a day. Then delete
`acme-svc-example`'s greeting domain and `acme-bff`'s `example/` app and put
yours in the same shape.

Enable the changelog hook once per clone:

```bash
git config core.hooksPath .githooks
```

## What this is not

Not a framework, and not something you depend on — it is a starting point you
own and edit. There is no upstream to merge from.

It targets **one box**. There is no orchestrator, no service mesh and no
horizontal scaling story, because at this size those cost more than they
return. The pieces that would have to change first are noted in
[specs/TECH-DEBT.md](specs/TECH-DEBT.md).
