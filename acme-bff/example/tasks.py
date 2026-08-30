import logging

from celery import shared_task
from django.core.management import call_command

logger = logging.getLogger(__name__)


@shared_task(name="example.sweep_example_jobs_task")
def sweep_example_jobs_task() -> None:
    """A thin shim over the management command.

    The logic lives in the command so it stays runnable by hand. An explicit
    `name` keeps the queue name stable and reviewable — an auto-derived one
    changes when the module moves, and in-flight messages are then orphaned.
    """
    logger.info("Running sweep_example_jobs")
    try:
        call_command("sweep_example_jobs", quiet=True)
    except Exception:
        logger.exception("sweep_example_jobs task failed")
        raise
