"""One suite every greeting provider must satisfy, unchanged.

A new adapter is not finished until it is registered in PROVIDERS below and
passes this file **unmodified**. If satisfying it requires editing an
assertion, either the adapter is wrong or the port is — and it is usually the
port (C-5).

Real adapters register by standing their provider's API up in respx inside
their own factory, so the assertions here never know which one they are
running against.
"""

from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass

import httpx
import pytest
import respx
from pydantic import SecretStr

from app.adapters.driven.providers.example.client import ExampleClient
from app.adapters.driven.providers.example.greeting_adapter import ExampleGreetingAdapter
from app.adapters.driven.providers.mock.adapter import FORCE_REJECT, MockProvider
from app.application.ports import GreetingProviderPort
from app.domain.enums import GreetingStatus
from app.domain.errors import ProviderError, ProviderNotConfiguredError
from tests.conftest import make_greeting_request

BASE_URL = "https://greetings.example.invalid"
CREDENTIAL = SecretStr("a-credential")


@dataclass(frozen=True)
class ProviderUnderTest:
    name: str
    greetings: GreetingProviderPort
    rejecting_recipient: str


ProviderFactory = Callable[[], AsyncIterator[ProviderUnderTest]]


@asynccontextmanager
async def mock_provider() -> AsyncIterator[ProviderUnderTest]:
    yield ProviderUnderTest(
        name="mock", greetings=MockProvider(), rejecting_recipient=FORCE_REJECT
    )


@asynccontextmanager
async def example_provider() -> AsyncIterator[ProviderUnderTest]:
    with respx.mock(base_url=BASE_URL) as mock:

        def respond(request: httpx.Request) -> httpx.Response:
            # The real provider 401s an empty credential; the mock has to as
            # well, or the contract's credential case only proves one of them.
            if request.headers.get("authorization") in (None, "Bearer "):
                return httpx.Response(401, json={"error": "unauthorized"})

            body = request.read().decode()
            if "REFUSE_ME" in body:
                return httpx.Response(
                    200,
                    json={
                        "id": "ex-1",
                        "state": "refused",
                        "refusalCode": "RECIPIENT_REJECTED",
                        "refusalReason": "blocked",
                    },
                )
            return httpx.Response(
                200,
                json={"id": "ex-1", "state": "sent", "renderedText": "Hello, Ada!"},
            )

        mock.post("/v1/greetings").mock(side_effect=respond)

        client = ExampleClient(BASE_URL, timeout_seconds=5.0)
        try:
            yield ProviderUnderTest(
                name="example",
                greetings=ExampleGreetingAdapter(client),
                rejecting_recipient="REFUSE_ME",
            )
        finally:
            await client.aclose()


PROVIDERS: list[ProviderFactory] = [mock_provider, example_provider]


@pytest.fixture(params=PROVIDERS, ids=lambda f: f.__name__)
async def provider(request) -> AsyncIterator[ProviderUnderTest]:
    async with request.param() as under_test:
        yield under_test


async def test_a_delivered_greeting_reports_delivered(provider):
    result = await provider.greetings.deliver_greeting(
        make_greeting_request(), CREDENTIAL
    )

    assert result.status is GreetingStatus.DELIVERED


async def test_the_caller_reference_survives_the_round_trip(provider):
    # Without this the BFF cannot match a verdict to the row that started it,
    # and a replayed delivery creates a second record (C-4).
    result = await provider.greetings.deliver_greeting(
        make_greeting_request(reference="ref-contract"), CREDENTIAL
    )

    assert result.reference == "ref-contract"


async def test_a_delivered_greeting_carries_a_provider_reference(provider):
    result = await provider.greetings.deliver_greeting(
        make_greeting_request(), CREDENTIAL
    )

    assert result.provider_reference


async def test_a_refusal_is_a_rejected_verdict_not_an_exception(provider):
    result = await provider.greetings.deliver_greeting(
        make_greeting_request(recipient=provider.rejecting_recipient), CREDENTIAL
    )

    assert result.status is GreetingStatus.REJECTED
    assert result.error_code


async def test_an_empty_credential_is_refused_the_same_way_everywhere(provider):
    with pytest.raises((ProviderNotConfiguredError, ProviderError)):
        await provider.greetings.deliver_greeting(
            make_greeting_request(), SecretStr("")
        )
