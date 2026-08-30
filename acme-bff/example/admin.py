from django.contrib import admin

from example.models import ExampleRecord


@admin.register(ExampleRecord)
class ExampleRecordAdmin(admin.ModelAdmin):
    list_display = ("recipient", "account", "status", "error_code", "created_at")
    list_filter = ("status", "is_active")
    search_fields = ("recipient", "provider_reference")
