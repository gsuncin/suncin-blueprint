"""Domain <-> this provider's wire format, in both directions."""

from typing import Any

from app.adapters.driven.providers.example.status_map import to_domain_status
from app.domain.models import GreetingRequest, GreetingResult


def build_greeting_payload(request: GreetingRequest) -> dict[str, Any]:
    """The provider's create-greeting body.

    Their field names, not ours: `to`, `lang`, `clientRef`.
    """
    return {
        "to": request.recipient,
        "lang": request.locale,
        "clientRef": request.reference,
    }


def parse_greeting_response(
    payload: dict[str, Any], request: GreetingRequest
) -> GreetingResult:
    status = to_domain_status(str(payload.get("state", "")))
    return GreetingResult(
        status=status,
        reference=request.reference,
        message=payload.get("renderedText"),
        provider_reference=payload.get("id"),
        error_code=payload.get("refusalCode"),
        error_message=payload.get("refusalReason"),
    )
