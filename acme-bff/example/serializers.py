from rest_framework import serializers

from example.models import ExampleRecord


class ExampleRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExampleRecord
        fields = (
            "id", "recipient", "locale", "status", "message",
            "provider_reference", "error_code", "error_message",
            "delivered_at", "is_active", "created_at", "updated_at",
        )
        # Everything the provider decides is read-only. A client that could set
        # `status` could mark its own jobs delivered.
        read_only_fields = (
            "id", "status", "message", "provider_reference", "error_code",
            "error_message", "delivered_at", "is_active", "created_at", "updated_at",
        )
