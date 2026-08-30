from django.contrib import admin

from audit.models import ProviderCall


@admin.register(ProviderCall)
class ProviderCallAdmin(admin.ModelAdmin):
    list_display = ("service", "operation", "status_code", "succeeded", "duration_ms", "created_at")
    list_filter = ("service", "succeeded", "direction")
    search_fields = ("correlation_id", "path")
    # Nothing here is editable. An audit log you can edit is not an audit log,
    # and the payload fields are the one place a missed redaction would show.
    readonly_fields = [field.name for field in ProviderCall._meta.fields]

    def has_add_permission(self, request) -> bool:
        return False

    def has_change_permission(self, request, obj=None) -> bool:
        return False
