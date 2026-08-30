"""What an Account's PLAN allows. Deliberately actor-free.

The DRF permission class cannot run on a Celery beat schedule, a management
command, or a webhook relay — none of them have a request or a user. If the
plan gate lived only there, every headless path would be an unmetered bypass.

So this takes an Account and nothing else, never raises, and never queries: it
can be called from anywhere, including inside a transaction holding a lock.

Role permissions are the *other* gate and live in users/permissions.py. Both
always. Never collapse them (C-2).
"""

from accounts.models import Account, Plan


class Entitlement:
    """One constant per gated capability."""

    EXAMPLE_JOBS = "example_jobs"
    BULK_EXPORT = "bulk_export"

    ALL = (EXAMPLE_JOBS, BULK_EXPORT)


PLAN_ENTITLEMENTS: dict[str, set[str]] = {
    Plan.FREE: set(),
    Plan.PRO: {Entitlement.EXAMPLE_JOBS, Entitlement.BULK_EXPORT},
}


def account_has(account: Account | None, entitlement: str) -> bool:
    """Does this account's plan include this capability?

    A missing account is not entitled. Failing closed is the only safe reading
    of "we do not know who this is".
    """
    if account is None:
        return False
    return entitlement in PLAN_ENTITLEMENTS.get(account.plan, set())


def entitlements_map(account: Account | None) -> dict[str, bool]:
    """Serialized to the frontend so the SPA never re-derives the rules."""
    return {name: account_has(account, name) for name in Entitlement.ALL}
