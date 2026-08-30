"""What a USER'S ROLE allows, inside an account that is already entitled.

The other half of C-2. This answers "may this person act?"; entitlements
answer "did this account buy the feature?". A plan denial must be able to say
"your plan does not include this" rather than "you have no permission", which
is only possible while the two stay separate.

ROLE_CAPABILITIES is the single source of truth. It is consumed by the DRF
permission class below AND serialized to the SPA by get_permissions_map, so
the frontend never re-implements the matrix and cannot drift from it.
"""

from django.db import models
from rest_framework import permissions


class UserRole(models.TextChoices):
    OWNER = "OWNER", "Owner"
    ADMIN = "ADMIN", "Admin"
    MEMBER = "MEMBER", "Member"
    VIEWER = "VIEWER", "Viewer"


class ResourceArea:
    ACCOUNT = "account"
    USERS = "users"
    EXAMPLE = "example"
    AUDIT = "audit"

    ALL = (ACCOUNT, USERS, EXAMPLE, AUDIT)


VIEW = "view"
MANAGE = "manage"

_FULL = {VIEW: True, MANAGE: True}
_READ_ONLY = {VIEW: True, MANAGE: False}
_NONE = {VIEW: False, MANAGE: False}

ROLE_CAPABILITIES: dict[str, dict[str, dict[str, bool]]] = {
    UserRole.OWNER: {area: _FULL for area in ResourceArea.ALL},
    UserRole.ADMIN: {
        ResourceArea.ACCOUNT: _READ_ONLY,
        ResourceArea.USERS: _FULL,
        ResourceArea.EXAMPLE: _FULL,
        ResourceArea.AUDIT: _READ_ONLY,
    },
    UserRole.MEMBER: {
        ResourceArea.ACCOUNT: _NONE,
        ResourceArea.USERS: _NONE,
        ResourceArea.EXAMPLE: _FULL,
        ResourceArea.AUDIT: _NONE,
    },
    UserRole.VIEWER: {
        ResourceArea.ACCOUNT: _NONE,
        ResourceArea.USERS: _NONE,
        ResourceArea.EXAMPLE: _READ_ONLY,
        ResourceArea.AUDIT: _NONE,
    },
}


def get_permissions_map(role: str) -> dict[str, dict[str, bool]]:
    """The whole matrix for one role, as the SPA receives it."""
    default = {area: _NONE for area in ResourceArea.ALL}
    return {
        area: dict(ROLE_CAPABILITIES.get(role, default).get(area, _NONE))
        for area in ResourceArea.ALL
    }


class HasFeaturePermission(permissions.BasePermission):
    """A view opts in with a `resource_area` attribute.

    Safe methods need `view`; everything else needs `manage`. A view with no
    resource_area is denied rather than allowed — forgetting to declare one
    must not silently open an endpoint.
    """

    message = "Your role does not allow this action."

    def has_permission(self, request, view) -> bool:
        area = getattr(view, "resource_area", None)
        if area is None:
            return False

        user = request.user
        if not user or not user.is_authenticated:
            return False
        if user.is_superuser:
            return True

        capability = VIEW if request.method in permissions.SAFE_METHODS else MANAGE
        return bool(ROLE_CAPABILITIES.get(user.role, {}).get(area, _NONE)[capability])
