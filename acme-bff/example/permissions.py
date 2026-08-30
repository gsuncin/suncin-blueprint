from rest_framework import permissions

from accounts.entitlements import Entitlement, account_has


class AccountHasExampleEntitlement(permissions.BasePermission):
    """The plan gate at the HTTP boundary.

    Carries its own `code` so the SPA can say "upgrade your plan" instead of
    "you have no permission" — two different problems with two different fixes,
    and telling them apart is the whole point of C-2.

    This is NOT the authoritative check. The service layer repeats it, because
    Celery and management commands never reach a permission class.
    """

    code = "PLAN_NOT_ENTITLED"
    message = "Your plan does not include this feature."

    def has_permission(self, request, view) -> bool:
        if request.method in permissions.SAFE_METHODS:
            return True
        return account_has(getattr(request.user, "account", None), Entitlement.EXAMPLE_JOBS)
