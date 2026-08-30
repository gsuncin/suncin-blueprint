from django.contrib import admin

from accounts.models import Account


@admin.register(Account)
class AccountAdmin(admin.ModelAdmin):
    list_display = ("name", "plan", "is_active", "created_at")
    list_filter = ("plan", "is_active")
    search_fields = ("name",)
