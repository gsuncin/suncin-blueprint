from django.core.management.base import BaseCommand

from common.choices import JobStatus
from example.models import ExampleRecord
from example.services import deliver_example_record


class Command(BaseCommand):
    """Retry records whose verdict never arrived.

    The safety net for lost webhooks (C-4). It is a management command rather
    than task-only logic so a human can run it by hand at 3am and watch what it
    does — which is the situation in which it matters.
    """

    help = "Re-attempt delivery for records still awaiting a verdict."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--limit", type=int, default=100)
        parser.add_argument("--quiet", action="store_true")

    def handle(self, *args, **options) -> None:
        pending = ExampleRecord.objects.filter(
            is_active=True,
            delivered_at__isnull=True,
            status__in=JobStatus.open_statuses(),
        ).select_related("account")[: options["limit"]]

        for record in pending:
            # deliver_example_record never raises, so one poisoned row cannot
            # stop the sweep from reaching the rest.
            result = deliver_example_record(record)
            if not options["quiet"]:
                self.stdout.write(f"{record.id}: {result.status}")
