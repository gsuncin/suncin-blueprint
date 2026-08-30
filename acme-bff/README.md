# acme-bff

Django/DRF. The system of record and the BFF: it owns every row, issues the
identity tokens the gateway verifies, and is the only party that talks to the
microservices.

## Why it is built this way

| Decision | Reason |
|---|---|
| Settings split by concern, not by environment | There is one environment shape and many knobs. A `base/dev/prod` split puts the interesting differences in a file nobody reads on the box |
| `core/settings/env.py` pins `.env` lookup | `python-decouple` walks **up** the tree, so the repo-root `.env` silently configured `manage.py test`. Whether a test passed depended on whether someone had run `make keys` |
| `DatabaseCache`, not Redis | Throttle counters must be shared across gunicorn workers. Local-memory silently multiplies every rate limit by the worker count, and this stack does not run Redis |
| Tokens are a thin shim over a management command | The logic stays runnable by hand at 3am, which is when it matters |
| Audit recorder opens its own savepoint | A failed audit INSERT would otherwise poison the caller's transaction, turning a lost log line into a 500 |

## Layout

```
core/
  settings/     split by concern; env.py pins where .env is read from
  service_client.py   the ONE way to call a microservice
  mixins.py     TenantQuerysetMixin — there is one, do not write a second
  crypto.py     make_fernet_helpers(setting_name) — one key per secret domain
  jwks.py       publishes the public half of the signing key
common/         BaseModelMixin, shared TextChoices
accounts/       the tenant, and entitlements.py (the PLAN gate — no actor)
users/          User, permissions.py (the ROLE gate), cookie-based JWT views
example/        the reference app shape. Copy this, delete the greeting domain
integrations/   clients for each microservice, over core/service_client.py
audit/          recorder.py, redaction.py, retention
```

## The two gates

They are separate and both always apply (C-2):

- `accounts/entitlements.py` — **what the plan includes.** Takes an Account and
  nothing else, so Celery and management commands reach the same verdict as an
  HTTP request. Never raises, never queries.
- `users/permissions.py` — **what the role allows.** A `ResourceArea` plus
  `view`/`manage`. `ROLE_CAPABILITIES` is the single source of truth and is
  serialized to the SPA, so the frontend never re-derives the rules.

The DRF permission class cannot run on a beat schedule, so the entitlement
check is **repeated inside the service layer**. That duplication is deliberate.

## Integrations never block the domain (C-1)

`example/services.py` is the reference. `deliver_example_record` never raises:
every failure returns the row with `status=ERROR` and a distinct `error_code`.
The client raises; the service layer catches and marks.

`_fail` redacts before writing and uses `save(update_fields=[...])`, so it
cannot blank a column a concurrent webhook just set.

## Running

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
cp .env.example .env

createdb acme_scratch
DEBUG=True DB_NAME=acme_scratch .venv/bin/python manage.py migrate
DEBUG=True DB_NAME=acme_scratch .venv/bin/python manage.py createcachetable
DEBUG=True DB_NAME=acme_scratch .venv/bin/python manage.py test
```

`DB_NAME` must be a **scratch** database: `DATABASES["default"]["TEST"]` sets
`MIRROR`, so the runner uses it directly rather than creating a throwaway.

Set `SHOW_TEST_LOGS=1` to see the application logs the runner otherwise
silences — the suite deliberately exercises failure paths, and their stack
traces bury the one line that says which test failed.

## Adding an app

1. Copy `example/`. Keep the file shape: `models`, `serializers`, `views`,
   `urls`, `permissions`, `services`, `tasks`, `management/commands`, tests.
2. Add an `Entitlement` constant **and** a `ResourceArea`.
3. Use `TenantQuerysetMixin`; filter `account_id` in `get_queryset`.
4. Soft delete. `perform_destroy` deactivates.
5. Anything that leaves the process goes through `core/service_client.py`, and
   the service function that calls it does not raise.
