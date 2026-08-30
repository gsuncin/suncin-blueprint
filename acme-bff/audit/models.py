from django.db import models

from common.models import BaseModelMixin


class CallDirection(models.TextChoices):
    OUTBOUND = "OUTBOUND", "Outbound"
    INBOUND = "INBOUND", "Inbound"


class ProviderCall(BaseModelMixin):
    """One recorded call across a service boundary.

    Exists to answer, months later: did we call them, when, with what, and what
    came back. Payloads are stored redacted — the redaction happens before the
    INSERT, not as a later cleanup pass, because a cleanup pass that fails
    leaves secrets in a table (C-3).
    """

    account = models.ForeignKey(
        "accounts.Account", on_delete=models.CASCADE, null=True, blank=True,
        related_name="provider_calls",
    )
    correlation_id = models.CharField(max_length=64, db_index=True)
    service = models.CharField(max_length=64)
    provider = models.CharField(max_length=64, blank=True)
    operation = models.CharField(max_length=128)
    direction = models.CharField(max_length=16, choices=CallDirection.choices)
    environment = models.CharField(max_length=32, blank=True)

    method = models.CharField(max_length=10)
    path = models.CharField(max_length=255)
    status_code = models.IntegerField(null=True, blank=True)
    duration_ms = models.IntegerField(null=True, blank=True)
    succeeded = models.BooleanField(default=False)

    request_payload = models.JSONField(null=True, blank=True)
    response_payload = models.JSONField(null=True, blank=True)
    error_message = models.TextField(blank=True)

    payloads_pruned_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["service", "operation", "-created_at"]),
            models.Index(fields=["account", "-created_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.service}.{self.operation} {self.status_code or 'unreachable'}"
