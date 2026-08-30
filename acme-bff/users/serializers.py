from rest_framework import serializers

from accounts.entitlements import entitlements_map
from users.models import User
from users.permissions import get_permissions_map


class UserSerializer(serializers.ModelSerializer):
    permissions = serializers.SerializerMethodField()
    entitlements = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = (
            "id", "email", "first_name", "last_name", "role",
            "account", "is_active", "permissions", "entitlements",
        )
        read_only_fields = ("id", "account", "permissions", "entitlements")

    def get_permissions(self, user: User) -> dict:
        return get_permissions_map(user.role)

    def get_entitlements(self, user: User) -> dict:
        return entitlements_map(user.account)
