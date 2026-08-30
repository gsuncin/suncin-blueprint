from pydantic import SecretStr

from app.adapters.driven.providers.example.client import ExampleClient
from app.adapters.driven.providers.example.mapper import (
    build_greeting_payload,
    parse_greeting_response,
)
from app.application.ports import GreetingProviderPort
from app.domain.models import GreetingRequest, GreetingResult


class ExampleGreetingAdapter(GreetingProviderPort):
    """Implements the greeting port against the example provider's HTTP API.

    Thin on purpose: transport and error translation live in the client,
    field-name knowledge lives in the mapper, status vocabulary lives in the
    status map. What is left here is the shape of the call.
    """

    def __init__(self, client: ExampleClient) -> None:
        self._client = client

    async def deliver_greeting(
        self, request: GreetingRequest, credential: SecretStr
    ) -> GreetingResult:
        payload = await self._client.post(
            "/v1/greetings", build_greeting_payload(request), credential
        )
        return parse_greeting_response(payload, request)
