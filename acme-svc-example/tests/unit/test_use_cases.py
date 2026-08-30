import pytest
from pydantic import SecretStr

from app.adapters.driven.providers.mock.adapter import (
    FORCE_PENDING,
    FORCE_REJECT,
    MockProvider,
)
from app.application.ports import GreetingProviderPort
from app.application.use_cases.say_hello import SayHello
from app.domain.enums import GreetingStatus
from app.domain.errors import ProviderError, ProviderNotConfiguredError
from app.domain.models import GreetingRequest, GreetingResult
from tests.conftest import TEST_CREDENTIAL, make_greeting_request

CREDENTIAL = SecretStr(TEST_CREDENTIAL)


class RaisingProvider(GreetingProviderPort):
    def __init__(self, error: Exception) -> None:
        self._error = error

    async def deliver_greeting(
        self, request: GreetingRequest, credential: SecretStr
    ) -> GreetingResult:
        raise self._error


async def test_delivers_through_the_provider():
    result = await SayHello(MockProvider()).execute(make_greeting_request(), CREDENTIAL)

    assert result.status is GreetingStatus.DELIVERED
    assert result.message == "Hello, Ada!"


async def test_a_rejection_is_a_verdict_not_an_exception():
    result = await SayHello(MockProvider()).execute(
        make_greeting_request(recipient=FORCE_REJECT), CREDENTIAL
    )

    assert result.status is GreetingStatus.REJECTED
    assert result.error_code == "RECIPIENT_REJECTED"


async def test_pending_keeps_the_provider_reference():
    result = await SayHello(MockProvider()).execute(
        make_greeting_request(recipient=FORCE_PENDING, reference="ref-7"), CREDENTIAL
    )

    assert result.status is GreetingStatus.PENDING
    assert result.provider_reference == "mock-ref-7"


@pytest.mark.parametrize(
    ("error", "expected_code"),
    [
        (ProviderError("PROVIDER_TIMEOUT", "timed out", retryable=True), "PROVIDER_TIMEOUT"),
        (ProviderNotConfiguredError("no credential"), "PROVIDER_NOT_CONFIGURED"),
        (RuntimeError("something nobody predicted"), "PROVIDER_ERROR"),
    ],
)
async def test_every_provider_failure_becomes_a_result(error, expected_code):
    # This is what lets the BFF follow C-1: it always gets a row back, never an
    # exception it has to translate.
    result = await SayHello(RaisingProvider(error)).execute(
        make_greeting_request(), CREDENTIAL
    )

    assert result.status is GreetingStatus.ERROR
    assert result.error_code == expected_code
    assert result.reference == "ref-1"


async def test_an_unexpected_error_does_not_leak_its_message():
    # The stack trace goes to the log; the caller gets a generic message,
    # because an arbitrary exception string can carry anything (C-3).
    result = await SayHello(RaisingProvider(RuntimeError("token=hunter2"))).execute(
        make_greeting_request(), CREDENTIAL
    )

    assert "hunter2" not in (result.error_message or "")
