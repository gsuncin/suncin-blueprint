---
name: project-testing
description: Use when validating monorepo changes, adding tests, debugging local or CI failures, or deciding which backend, frontend, or infrastructure checks a change requires.
---

# Testing

The exit gate is `specs/CONSTITUTION.md` C-8: **the full suite for the project
you touched, green, with the output shown.**

## Everything at once

```bash
./scripts/run-all-tests.sh          # stops at the first red
```

## Backend test environment

```bash
createdb acme_scratch
DEBUG=True DB_NAME=acme_scratch python acme-bff/manage.py migrate
DEBUG=True DB_NAME=acme_scratch python acme-bff/manage.py test
```

The env vars are load-bearing. `DATABASES["default"]["TEST"]` sets `MIRROR`, so
Django does **not** create a throwaway database — it uses `DB_NAME` directly.
Point it at a scratch database you created for the purpose. Run `migrate`
against it first or every test errors with `relation ... does not exist`.

Because it is a mirror, `TransactionTestCase._fixture_teardown` skips the
flush, so such a test **leaks rows into the scratch database** and breaks later
tests in the same run and in every subsequent run until you recreate it.

## Which suite for which change

| You changed | Run |
|---|---|
| A model or migration | Backend suite, plus a data-survival test if it backfills |
| A service function | Backend, including its failure path (C-1) |
| An endpoint | Backend, covering tenancy (C-6) and both gates (C-2) |
| A port or adapter | Service pytest **and** the contract suite |
| Gateway routing or auth | `auth` pytest + `scripts/verify-isolation.sh` |
| A component | `test:unit` |
| A route | `test:unit` + `test:e2e` |
| The landing entry | `test:unit` (byte budget) + `test:lighthouse` |
| Compose, Traefik, Terraform | `verify-isolation.sh`, `terraform validate` |

## Frontend

```bash
npm --prefix acme-web run lint
npm --prefix acme-web run build      # tsc lives here — type errors surface here
npm --prefix acme-web run test:unit  # NOT "run test" — no such script
npm --prefix acme-web run test:e2e
npm --prefix acme-web run test:lighthouse
```

## Infrastructure

```bash
./scripts/verify-isolation.sh                    # C-12, also runs in CI
terraform fmt -check -recursive acme-tf
terraform -chdir=acme-tf/envs/oci init -backend=false && \
terraform -chdir=acme-tf/envs/oci validate
```

## Before you call it done

- [ ] The new test failed before it passed.
- [ ] The **full** suite for every project you touched is green.
- [ ] You pasted the output, not a summary of it.
- [ ] Nothing was skipped, loosened or deleted to get there.
- [ ] If something is still red, you reported it as **blocked, not done**.
