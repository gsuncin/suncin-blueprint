from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.domain.models import GreetingRequest
from app.main import create_app

TEST_SECRET = "test-secret"
TEST_CREDENTIAL = "test-provider-credential"


@pytest.fixture
def settings() -> Settings:
    # _env_file=None isolates the suite from a developer's local .env. Without
    # it the tests pass on one machine and fail in CI, or worse, the reverse.
    return Settings(provider_mode="mock", jwt_secret=TEST_SECRET, _env_file=None)


@pytest.fixture
def client(settings: Settings):
    with TestClient(create_app(settings)) as test_client:
        yield test_client


def make_token(
    secret: str = TEST_SECRET,
    *,
    issuer: str = "acme-bff",
    audience: str = "acme-svc-example",
    expires_in: int = 60,
) -> str:
    now = datetime.now(tz=timezone.utc)
    return jwt.encode(
        {
            "iss": issuer,
            "aud": audience,
            "iat": now,
            "exp": now + timedelta(seconds=expires_in),
        },
        secret,
        algorithm="HS256",
    )


@pytest.fixture
def auth_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {make_token()}",
        "X-Provider-Credential": TEST_CREDENTIAL,
    }


def greeting_payload(**overrides: Any) -> dict[str, Any]:
    """The wire body, in camelCase as the BFF sends it."""
    return {"recipient": "Ada", "locale": "en", "reference": "ref-1", **overrides}


def make_greeting_request(**overrides: Any) -> GreetingRequest:
    return GreetingRequest(
        **{"recipient": "Ada", "locale": "en", "reference": "ref-1", **overrides}
    )
