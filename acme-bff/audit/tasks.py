import logging

from celery import shared_task
from django.core.management import call_command

logger = logging.getLogger(__name__)


@shared_task(name="audit.prune_audit_payloads_task")
def prune_audit_payloads_task() -> None:
    logger.info("Running prune_audit_payloads")
    try:
        call_command("prune_audit_payloads", quiet=True)
    except Exception:
        logger.exception("prune_audit_payloads task failed")
        raise
