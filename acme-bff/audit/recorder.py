"""Record a cross-boundary call without ever becoming the reason one fails."""

import logging
import uuid
from dataclasses import dataclass, field
from typing import Any

import requests
from django.db import transaction as db_transaction

from audit.models import CallDirection, ProviderCall
from audit.redaction import redact_payload, redact_text

logger = logging.getLogger(__name__)


@dataclass
class AuditContext:
    """Assembled by the service layer, threaded through the client.

    The service layer is the only place that knows the business meaning of a
    call — which account, which operation, which provider. The client knows the
    HTTP facts. Splitting it this way keeps the client generic.
    """

    service: str
    operation: str
    provider: str = ""
    account_id: Any = None
    environment: str = ""
    direction: str = CallDirection.OUTBOUND
    correlation_id: str = field(default_factory=lambda: uuid.uuid4().hex)


def record_provider_call(
    audit: AuditContext | None,
    *,
    method: str,
    path: str,
    request_payload: Any,
    outcome: "requests.Response | Exception",
    started: float,
) -> None:
    """Write one audit row. Never raises.

    Two properties make this safe to call from anywhere:

    1. It swallows its own failures. An audit table that is full, locked, or
       missing a migration must not take down the operation it is observing.
    2. It opens its OWN savepoint. Without that, a failed INSERT marks the
       caller's transaction as broken, and every subsequent query in that
       request fails with "current transaction is aborted" — turning a lost log
       line into a 500.
    """
    if audit is None:
        return

    import time

    duration_ms = int((time.monotonic() - started) * 1000)

    try:
        if isinstance(outcome, Exception):
            response = getattr(outcome, "response", None)
            status_code = getattr(response, "status_code", None)
            succeeded = False
            response_payload = _safe_body(response)
            error_message = redact_text(str(outcome))[:2000]
        else:
            status_code = outcome.status_code
            succeeded = outcome.ok
            response_payload = _safe_body(outcome)
            error_message = ""

        with db_transaction.atomic():
            ProviderCall.objects.create(
                account_id=audit.account_id,
                correlation_id=audit.correlation_id,
                service=audit.service,
                provider=audit.provider,
                operation=audit.operation,
                direction=audit.direction,
                environment=audit.environment,
                method=method.upper(),
                path=path[:255],
                status_code=status_code,
                duration_ms=duration_ms,
                succeeded=succeeded,
                request_payload=redact_payload(request_payload),
                response_payload=response_payload,
                error_message=error_message,
            )
    except Exception:
        logger.exception(
            "Failed to record provider call %s %s; continuing", method, path
        )


def _safe_body(response: Any) -> Any:
    if response is None:
        return None
    try:
        return redact_payload(response.json())
    except Exception:
        text = getattr(response, "text", "") or ""
        return {"raw": redact_text(text[:2000])} if text else None
