class TenantQuerysetMixin:
    """Scope a queryset to the requesting user's account.

    There is no tenant middleware and no thread-local to fall back on: if a
    view forgets to call this, it leaks across tenants silently. That is why
    C-6 says every queryset filters explicitly, and why this lives in one place
    rather than being copied per app.
    """

    def filter_by_tenant(self, queryset):
        user = self.request.user
        if user.is_staff or user.is_superuser:
            return queryset
        return queryset.filter(account_id=user.account_id)
