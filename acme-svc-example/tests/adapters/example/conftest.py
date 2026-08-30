from collections.abc import AsyncIterator

import pytest
import respx

from app.adapters.driven.providers.example.client import ExampleClient
from app.adapters.driven.providers.example.greeting_adapter import ExampleGreetingAdapter

BASE_URL = "https://greetings.example.invalid"


@pytest.fixture
def mock_api():
    with respx.mock(base_url=BASE_URL, assert_all_called=False) as mock:
        yield mock


@pytest.fixture
async def adapter() -> AsyncIterator[ExampleGreetingAdapter]:
    client = ExampleClient(BASE_URL, timeout_seconds=5.0)
    try:
        yield ExampleGreetingAdapter(client)
    finally:
        await client.aclose()
