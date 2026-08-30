# acme-svc-example

A stateless microservice in ports & adapters. It says hello. That is the whole
domain — the point is the **shape**, which every other service in this monorepo
copies.

## Why it is built this way

| Decision | Reason |
|---|---|
| No database | The BFF is the only stateful party. This service can be redeployed, scaled or destroyed without a migration (C-3) |
| Credential arrives per request, in a header | Nothing to leak at rest here; the audit log records bodies and never headers |
| Verdicts return HTTP 200 | A provider refusing is a fact about the world, not a bug in the caller. That is what lets the BFF store a failure-marked row rather than raise (C-1, C-5) |
| Two real adapters, not one plus a mock | The contract suite only proves something if it runs against more than one implementation |
| Eager composition root | A box configured for a provider this build cannot serve fails at startup, not on the first real request |

## Layout

```
app/
├── domain/        enums, errors, frozen models. Knows nothing about HTTP or providers.
├── application/   ports (ABC) + use cases. Knows the domain; not the wire.
└── adapters/
    ├── driving/   what drives us: the HTTP API, its schemas, its auth
    └── driven/    what we drive: providers/<name>/, five files each
```

**Provider vocabulary never appears above `adapters/driven/providers/<name>/`.**
`container.py` is the one exception — it has to name a provider to build it.

## Running

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/pytest -q

cp .env.example .env
.venv/bin/uvicorn app.main:app --reload --port 8000
```

Defaults to the mock provider, so it runs with no credentials and no network.

## Adding a provider

1. Create `adapters/driven/providers/<name>/` with the five-file shape:
   `client.py` (transport + error translation), `<thing>_adapter.py` (one per
   port), `mapper.py` (domain ↔ wire), `status_map.py`, optionally `auth.py`.
2. Add the branch to `container.py` and the literal to `config.py`.
3. **Register it in `PROVIDERS` in `tests/contract/test_provider_contract.py`.**

If step 3 requires editing an assertion, stop: either the adapter is wrong or
the port is. Fix the port.

If your diff touched `application/`, the port is wrong (C-5, OCP).
