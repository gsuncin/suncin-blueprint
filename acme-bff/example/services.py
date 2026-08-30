"""Domain orchestration for example records.

Every public function here NEVER RAISES on an integration failure. It writes
the failure onto the row and returns it, so scheduling, billing and reporting
all keep working while a provider is down (C-1).
"""

import logging

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from accounts.entitlements import Entitlement, account_has
from audit.recorder import AuditContext
from audit.redaction import redact_text
from common.choices import JobStatus
from core.crypto import EncryptionError, decrypt_provider_credential
from example.models import ExampleRecord
from integrations.example_client import ServiceError, deliver_greeting

logger = logging.getLogger(__name__)


class CredentialUnavailable(Exception):
    """The account has no stored provider credential.

    Not an EncryptionError: nothing failed, there is simply nothing configured
    yet. Conflating the two sends someone to debug a key that is fine.
    """

# Maps the service's domain vocabulary onto ours. They are deliberately the
# same words today; this exists so that they are allowed to diverge later
# without the mapping being scattered across call sites.
_SERVICE_STATUS = {
    "DELIVERED": JobStatus.DELIVERED,
    "PENDING": JobStatus.PENDING,
    "REJECTED": JobStatus.REJECTED,
    "ERROR": JobStatus.ERROR,
}


def deliver_example_record(record: ExampleRecord) -> ExampleRecord:
    """Deliver one record's greeting. Never raises.

    On any failure the row comes back with status=ERROR and a distinct
    error_code the caller — or a human reading the table — can act on.
    """
    try:
        return _attempt_delivery(record)
    except Exception as exc:
        logger.exception("Unexpected error delivering record %s", record.id)
        return _fail(record, "UNEXPECTED_ERROR", str(exc))


def _attempt_delivery(record: ExampleRecord) -> ExampleRecord:
    # Repeated here on purpose: the DRF permission class cannot see the sweep
    # or a management command, and this is the path they take (C-2).
    if not account_has(record.account, Entitlement.EXAMPLE_JOBS):
        return _fail(record, "PLAN_NOT_ENTITLED", "The account's plan does not include this")

    if record.delivered_at is not None:
        # Already settled. Doing nothing is the correct behaviour for a replay.
        return record

    try:
        credential = _live_credential(record)
    except CredentialUnavailable as exc:
        return _fail(record, "CREDENTIAL_UNAVAILABLE", str(exc))
    except EncryptionError as exc:
        return _fail(record, "DECRYPTION_ERROR", str(exc))

    audit = AuditContext(
        service="acme-svc-example",
        operation="deliver_greeting",
        account_id=record.account_id,
        environment=settings.SENTRY_ENVIRONMENT,
    )

    try:
        payload = deliver_greeting(
            recipient=record.recipient,
            locale=record.locale,
            reference=str(record.id),
            credential=credential,
            audit=audit,
        )
    except ServiceError as exc:
        # status_code is None when the service could not be reached at all,
        # which is the case a sweep should retry.
        code = "SERVICE_UNREACHABLE" if exc.status_code is None else "SERVICE_ERROR"
        return _fail(record, code, str(exc))

    return apply_delivery_result(record, payload)


def apply_delivery_result(record: ExampleRecord, payload: dict) -> ExampleRecord:
    """Write a verdict onto the row, once.

    Takes the row lock and re-reads inside it: checking `delivered_at` before
    the lock proves nothing, because a concurrent webhook can set it between
    the check and the write (C-4).
    """
    with transaction.atomic():
        locked = ExampleRecord.objects.select_for_update().get(pk=record.pk)

        if locked.delivered_at is not None:
            return locked

        status = _SERVICE_STATUS.get(payload.get("status", ""), JobStatus.ERROR)
        locked.status = status
        locked.message = payload.get("message") or ""
        locked.provider_reference = payload.get("providerReference") or ""
        locked.error_code = payload.get("errorCode") or ""
        locked.error_message = redact_text(payload.get("errorMessage") or "")

        if status == JobStatus.DELIVERED:
            locked.delivered_at = timezone.now()

        locked.save(
            update_fields=[
                "status", "message", "provider_reference", "error_code",
                "error_message", "delivered_at", "updated_at",
            ]
        )
        return locked


def _live_credential(record: ExampleRecord) -> str:
    """The single seam where a stored provider credential is decrypted.

    Kept as a function rather than inlined because this is where an OAuth
    refresh would go when a real provider needs one — and because there should
    be exactly one place to audit for C-3.

    Raises CredentialUnavailable when the account has not connected a provider.
    That is a normal state, distinct from a decryption failure: one means "set
    this up", the other means "the key is wrong", and they need different
    error codes so the caller can tell them apart.
    """
    if not settings.PROVIDER_CREDENTIAL_ENCRYPTION_KEY:
        # Local and CI run the service's mock provider, which accepts any
        # non-empty credential. A real deployment configures the key.
        return "mock-credential"

    ciphertext = record.account.provider_credential_encrypted
    if not ciphertext:
        raise CredentialUnavailable("This account has not connected a provider yet")

    return decrypt_provider_credential(ciphertext)


def _fail(record: ExampleRecord, error_code: str, error_message: str) -> ExampleRecord:
    """The one way a record is marked failed.

    Redacts at the sink, so a provider that echoed a credential into its error
    text cannot write it to the database (C-3). Uses update_fields so it cannot
    blank a column a concurrent webhook just set.
    """
    record.status = JobStatus.ERROR
    record.error_code = error_code
    record.error_message = redact_text(error_message)[:2000]
    record.save(update_fields=["status", "error_code", "error_message", "updated_at"])

    logger.warning(
        "Example record %s failed: %s", record.id, error_code,
        extra={"event": "example_record_failed", "account_id": str(record.account_id)},
    )
    return record
