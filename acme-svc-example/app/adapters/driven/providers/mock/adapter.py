"""Deterministic in-process provider.

Not a test double bolted on beside the real thing — a second real
implementation of the port, which is what makes the contract suite meaningful
and what lets local dev and CI run with no credentials at all.

Deterministic on purpose: the same request produces the same result, so a
replay in a test is genuinely a replay (C-4).
"""

from pydantic import SecretStr

from app.application.ports import GreetingProviderPort
from app.domain.enums import GreetingStatus
from app.domain.errors import ProviderNotConfiguredError
from app.domain.models import GreetingRequest, GreetingResult

# Markers in the recipient drive the unhappy paths end to end, so an e2e test
# can exercise a rejection without a provider that misbehaves on demand.
FORCE_REJECT = "FORCE_REJECT"
FORCE_PENDING = "FORCE_PENDING"

GREETINGS = {
    "en": "Hello, {recipient}!",
    "pt": "Olá, {recipient}!",
    "es": "¡Hola, {recipient}!",
}


class MockProvider(GreetingProviderPort):
    async def deliver_greeting(
        self, request: GreetingRequest, credential: SecretStr
    ) -> GreetingResult:
        if not credential.get_secret_value():
            raise ProviderNotConfiguredError("Empty credential")

        if FORCE_REJECT in request.recipient:
            return GreetingResult(
                status=GreetingStatus.REJECTED,
                reference=request.reference,
                error_code="RECIPIENT_REJECTED",
                error_message="The provider refused this recipient",
            )

        if FORCE_PENDING in request.recipient:
            return GreetingResult(
                status=GreetingStatus.PENDING,
                reference=request.reference,
                provider_reference=f"mock-{request.reference}",
            )

        template = GREETINGS.get(request.locale, GREETINGS["en"])
        return GreetingResult(
            status=GreetingStatus.DELIVERED,
            reference=request.reference,
            message=template.format(recipient=request.recipient),
            provider_reference=f"mock-{request.reference}",
        )
