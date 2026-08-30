import httpx
import pytest
from pydantic import SecretStr

from app.domain.enums import GreetingStatus
from app.domain.errors import ProviderError, ProviderNotConfiguredError
from tests.conftest import make_greeting_request

CREDENTIAL = SecretStr("a-credential")


async def test_maps_the_provider_payload_onto_the_domain(mock_api, adapter):
    mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(
            200, json={"id": "ex-42", "state": "sent", "renderedText": "Hello, Ada!"}
        )
    )

    result = await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert result.status is GreetingStatus.DELIVERED
    assert result.provider_reference == "ex-42"
    assert result.message == "Hello, Ada!"


async def test_sends_the_providers_field_names(mock_api, adapter):
    route = mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(200, json={"id": "ex-1", "state": "sent"})
    )

    await adapter.deliver_greeting(
        make_greeting_request(recipient="Grace", reference="ref-9"), CREDENTIAL
    )

    assert route.calls.last.request.read() == (
        b'{"to":"Grace","lang":"en","clientRef":"ref-9"}'
    )


async def test_an_unknown_status_is_pending_not_error(mock_api, adapter):
    # A provider adding a status we have not seen has not failed. Treating it
    # as an error would settle records that are still in flight.
    mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(200, json={"id": "ex-1", "state": "throttled"})
    )

    result = await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert result.status is GreetingStatus.PENDING


async def test_a_timeout_is_retryable(mock_api, adapter):
    mock_api.post("/v1/greetings").mock(side_effect=httpx.TimeoutException("slow"))

    with pytest.raises(ProviderError) as exc:
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert exc.value.code == "PROVIDER_TIMEOUT"
    assert exc.value.retryable is True


@pytest.mark.parametrize("status_code", [500, 502, 503, 429])
async def test_server_errors_and_throttling_are_retryable(mock_api, adapter, status_code):
    mock_api.post("/v1/greetings").mock(return_value=httpx.Response(status_code))

    with pytest.raises(ProviderError) as exc:
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert exc.value.retryable is True


async def test_a_bad_request_is_not_retryable(mock_api, adapter):
    mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(400, text="recipient is not a valid address")
    )

    with pytest.raises(ProviderError) as exc:
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert exc.value.code == "PROVIDER_REJECTED"
    assert exc.value.retryable is False


async def test_a_rejected_credential_is_not_a_provider_outage(mock_api, adapter):
    mock_api.post("/v1/greetings").mock(return_value=httpx.Response(401))

    with pytest.raises(ProviderNotConfiguredError):
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)


async def test_an_echoed_credential_is_scrubbed_from_the_error(mock_api, adapter):
    # Providers echo the request back in error bodies. That text ends up in an
    # error_message column and in logs, so it must not carry the secret (C-3).
    mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(
            400, text='{"echo": {"Authorization": "Bearer a-credential"}}'
        )
    )

    with pytest.raises(ProviderError) as exc:
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert "a-credential" not in exc.value.message
    assert "[REDACTED]" in exc.value.message


async def test_a_non_json_body_is_a_malformed_response(mock_api, adapter):
    mock_api.post("/v1/greetings").mock(
        return_value=httpx.Response(200, text="<html>maintenance</html>")
    )

    with pytest.raises(ProviderError) as exc:
        await adapter.deliver_greeting(make_greeting_request(), CREDENTIAL)

    assert exc.value.code == "PROVIDER_MALFORMED_RESPONSE"
