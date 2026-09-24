"""Call every function `integrations/` exports, against the real services.

**This is the only thing in the repository that crosses the BFF→service
boundary for real.** Everything else asserts one half of the wire contract
against a mock of the other half, which is TD-1: both suites stay green while
the two ends disagree. A header renamed on one side, a settings name no
delivery path sets, an issuer no compose entry passes — each is invisible to
every passing test and each is found by making one real call.

**The coverage rule is derivation, not a list.** A client function that nothing
in the BFF calls is the one most likely to be wrong, and walking the screens
would never reach it. Walking `__all__` does.

Three ways this fails closed, each of them the shape of a bug that ships:

1. No `*_client` module found at all, or a module whose `__all__` is empty — a
   loop over nothing is a pass that ran no tests.
2. An exported function with no probe below. Adding a client and not probing it
   is how a service gets built, tested, released and then never wired.
3. A probe naming a function that is no longer exported — a check quietly
   measuring something that has been deleted.

It lives in `common/` rather than beside the code it exercises because
`integrations` is not in `INSTALLED_APPS`, so Django would never discover a
management command inside it. `scripts/rehearse-stack.sh` is what runs it.

    docker compose exec -T bff python manage.py rehearse_integrations
"""

import importlib
import inspect
import pkgutil
from typing import Any, Callable

from django.core.management.base import BaseCommand, CommandError

import integrations

# A dev-only literal. The services run their mock providers here and only check
# that the credential is non-empty; a real per-tenant token is Fernet-encrypted
# on `Account` and never appears in a source file (C-3).
REHEARSAL_CREDENTIAL = "rehearsal-credential-not-a-real-token"
REFERENCE = "rehearsal-probe"

# One entry per exported function: the keyword arguments to call it with, and
# the response keys the BFF would go on to read. The *set* of entries is never
# trusted — it is checked against every module's `__all__` below, in both
# directions, so this table cannot silently fall behind the code.
#
# The expected keys matter as much as the call succeeding. A route that answers
# 200 with a body the caller cannot read is the same defect one layer along, and
# the services spell their wire camelCase (C-5) while the BFF is snake_case
# everywhere else — which is exactly the kind of disagreement two mocked suites
# cannot see.
PROBES: dict[str, dict[str, Any]] = {
    "example_client.deliver_greeting": {
        "kwargs": {
            "recipient": "Ada Lovelace",
            "locale": "en",
            "reference": REFERENCE,
            "credential": REHEARSAL_CREDENTIAL,
        },
        "expect_keys": ["status", "reference"],
    },
}


def exported_functions() -> dict[str, Callable[..., Any]]:
    """Every callable named in an `integrations/*_client.py` module's `__all__`.

    Derived, and loudly empty-intolerant: a `CommandError` rather than an empty
    dict, because every instance of this bug is a loop over nothing reported as
    a pass. Exported names that are not functions — `ServiceError` is one,
    re-exported by every client — are skipped, and the caller's probe-table
    check is what stops that skip from hiding anything.
    """
    found: dict[str, Callable[..., Any]] = {}
    module_names = [
        name
        for _, name, _ in pkgutil.iter_modules(integrations.__path__)
        if name.endswith("_client")
    ]
    if not module_names:
        raise CommandError(
            "no integrations/*_client.py module was found — refusing to report success "
            "about a boundary this command never crossed"
        )

    for module_name in sorted(module_names):
        module = importlib.import_module(f"integrations.{module_name}")
        exports = getattr(module, "__all__", None)
        if not exports:
            raise CommandError(
                f"integrations.{module_name} exports nothing via __all__; this check "
                "derives its coverage from __all__ and cannot cover a module without one"
            )
        for export in exports:
            attribute = getattr(module, export)
            if inspect.isfunction(attribute):
                found[f"{module_name}.{export}"] = attribute

    return found


class Command(BaseCommand):
    help = "Call every function integrations/ exports against the running services."

    def handle(self, *args, **options) -> None:
        functions = exported_functions()
        unprobed = sorted(set(functions) - set(PROBES))
        stale = sorted(set(PROBES) - set(functions))
        if unprobed or stale:
            raise CommandError(
                "the probe table and integrations/__all__ disagree.\n"
                f"  exported but never called here: {unprobed or 'none'}\n"
                f"  probed but no longer exported:  {stale or 'none'}\n"
                "Every exported function gets a real call. A dead function with a wrong "
                "body is a deployment waiting to discover it."
            )

        failures: list[str] = []
        for name in sorted(functions):
            probe = PROBES[name]
            self.stdout.write(f"  calling {name} ...", ending=" ")
            try:
                payload = functions[name](audit=None, **probe["kwargs"])
            except Exception as exc:  # noqa: BLE001 — the verdict is the point
                status = getattr(exc, "status_code", None)
                detail = f"{type(exc).__name__}: {exc}" + (
                    f" (status {status})" if status else ""
                )
                self.stdout.write(self.style.ERROR("FAILED"))
                failures.append(f"{name} — {detail}")
                continue

            missing = [key for key in probe["expect_keys"] if key not in payload]
            if missing:
                self.stdout.write(self.style.ERROR("WRONG SHAPE"))
                failures.append(
                    f"{name} — answered 200 with no {missing} in the body; "
                    f"got keys {sorted(payload)}"
                )
                continue

            summary = {key: payload[key] for key in probe["expect_keys"]}
            self.stdout.write(self.style.SUCCESS(f"ok {summary}"))

        if failures:
            raise CommandError(
                "the BFF and its services disagree on the wire:\n"
                + "\n".join(f"  - {failure}" for failure in failures)
            )

        self.stdout.write(
            self.style.SUCCESS(
                f"\n{len(functions)} exported integration functions called for real, "
                "across a real network, against real services."
            )
        )
