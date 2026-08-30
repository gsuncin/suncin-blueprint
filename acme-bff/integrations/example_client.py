"""The BFF's half of the wire contract with acme-svc-example.

Header names and status strings are asserted here and in the service's own
suite, but never end to end — see TD-1. A rename on one side passes both.
"""

from typing import Any

from django.conf import settings

from audit.recorder import AuditContext
from core.service_client import ServiceClient, ServiceError

PROVIDER_CREDENTIAL_HEADER = "X-Provider-Credential"

__all__ = ["ServiceError", "deliver_greeting"]


def _client() -> ServiceClient:
    return ServiceClient(
        base_url=settings.EXAMPLE_SERVICE_URL,
        jwt_secret=settings.EXAMPLE_SERVICE_JWT_SECRET,
        audience=settings.EXAMPLE_SERVICE_JWT_AUDIENCE,
    )


def deliver_greeting(
    *, recipient: str, locale: str, reference: str, credential: str, audit: AuditContext | None
) -> dict[str, Any]:
    """Ask the service to deliver one greeting. Raises ServiceError.

    The credential goes in `secret_headers`, which the client merges into the
    request and never hands to the audit recorder. Putting it in the body would
    write it to the audit table on the very next line (C-3).
    """
    return _client().request(
        "POST",
        "/internal/greetings",
        audit=audit,
        json={"recipient": recipient, "locale": locale, "reference": reference},
        secret_headers={PROVIDER_CREDENTIAL_HEADER: credential},
    )
