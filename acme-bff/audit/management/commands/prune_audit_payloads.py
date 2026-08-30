from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from audit.models import ProviderCall


class Command(BaseCommand):
    """Two-horizon retention for the provider audit log.

    Payloads are the sensitive and bulky half, so they go first. The metadata
    row survives longer because "did we call them, and when" is the question
    the audit log exists to answer, and it costs almost nothing to keep.
    """

    help = "Blank old audit payloads, then delete rows past the longer horizon."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--quiet", action="store_true")

    def handle(self, *args, **options) -> None:
        now = timezone.now()

        payload_cutoff = now - timedelta(days=settings.AUDIT_PAYLOAD_RETENTION_DAYS)
        blanked = ProviderCall.objects.filter(
            created_at__lt=payload_cutoff, payloads_pruned_at__isnull=True
        ).update(request_payload=None, response_payload=None, payloads_pruned_at=now)

        row_cutoff = now - timedelta(days=settings.AUDIT_ROW_RETENTION_DAYS)
        deleted, _ = ProviderCall.objects.filter(created_at__lt=row_cutoff).delete()

        if not options["quiet"]:
            self.stdout.write(f"payloads blanked: {blanked}, rows deleted: {deleted}")
