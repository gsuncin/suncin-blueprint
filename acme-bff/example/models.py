from django.db import models

from common.choices import JobStatus
from common.models import BaseModelMixin


class ExampleRecord(BaseModelMixin):
    """A record that owns an outbound job. The reference shape for a new app.

    `status`, `error_code` and `error_message` are the C-1 machinery: a failed
    integration writes them and returns the row, so the domain always has an
    answer even when the provider does not.
    """

    account = models.ForeignKey(
        "accounts.Account", on_delete=models.CASCADE, related_name="example_records"
    )
    recipient = models.CharField(max_length=120)
    locale = models.CharField(max_length=8, default="en")

    status = models.CharField(max_length=32, choices=JobStatus.choices, default=JobStatus.PENDING)
    message = models.TextField(blank=True)
    provider_reference = models.CharField(max_length=128, blank=True)
    error_code = models.CharField(max_length=64, blank=True)
    error_message = models.TextField(blank=True)

    # Nullable, and set exactly once. This is the idempotency key: a replayed
    # verdict finds it already set and creates no second delivery (C-4).
    delivered_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["account", "status", "-created_at"])]

    def __str__(self) -> str:
        return f"{self.recipient} ({self.status})"
