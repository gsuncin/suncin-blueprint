import pytest
from pydantic import ValidationError

from app.domain.enums import GreetingStatus
from app.domain.models import GreetingRequest, GreetingResult


def test_greeting_request_is_frozen():
    request = GreetingRequest(recipient="Ada", locale="en", reference="ref-1")
    with pytest.raises(ValidationError):
        request.recipient = "Grace"


def test_greeting_request_rejects_an_empty_recipient():
    with pytest.raises(ValidationError):
        GreetingRequest(recipient="", locale="en", reference="ref-1")


def test_greeting_request_defaults_to_english():
    assert GreetingRequest(recipient="Ada", reference="ref-1").locale == "en"


def test_failed_result_carries_the_reference_back():
    # The reference is how the BFF matches a verdict to the row that started
    # it; losing it on the failure path would orphan the record.
    result = GreetingResult.failed("ref-9", "PROVIDER_TIMEOUT", "timed out")

    assert result.status is GreetingStatus.ERROR
    assert result.reference == "ref-9"
    assert result.error_code == "PROVIDER_TIMEOUT"
