"""The full inbound-auth matrix.

Reusable as-is for any service in this monorepo: change the audience and the
env var name and the cases are identical.
"""

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from tests.conftest import TEST_CREDENTIAL, TEST_SECRET, greeting_payload, make_token

CREDENTIAL_HEADER = {"X-Provider-Credential": TEST_CREDENTIAL}


def post(client: TestClient, token: str | None):
    headers = dict(CREDENTIAL_HEADER)
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    return client.post("/internal/greetings", json=greeting_payload(), headers=headers)


def test_a_valid_token_is_accepted(client):
    assert post(client, make_token()).status_code == 200


def test_a_missing_token_is_401(client):
    assert post(client, None).status_code == 401


def test_a_token_signed_with_the_wrong_secret_is_401(client):
    assert post(client, make_token(secret="not-the-secret")).status_code == 401


def test_an_expired_token_is_401(client):
    assert post(client, make_token(expires_in=-10)).status_code == 401


def test_a_token_for_another_audience_is_401(client):
    # A token minted for a sibling service must not work here, or a compromise
    # of one service's caller grants access to all of them.
    assert post(client, make_token(audience="acme-svc-other")).status_code == 401


def test_a_token_from_an_unknown_issuer_is_401(client):
    assert post(client, make_token(issuer="somebody-else")).status_code == 401


def test_no_secret_in_mock_mode_runs_open():
    # Local dev and CI have no secret and no provider credentials. This is the
    # only configuration in which unauthenticated access is allowed.
    settings = Settings(provider_mode="mock", jwt_secret="", _env_file=None)
    with TestClient(create_app(settings)) as client:
        assert post(client, None).status_code == 200


def test_no_secret_in_a_real_provider_mode_fails_closed():
    # The dangerous configuration: a real provider wired up with no inbound
    # auth. 503 rather than 401 because the box is misconfigured, not the
    # caller.
    settings = Settings(
        provider_mode="example",
        jwt_secret="",
        example_base_url="https://greetings.example.invalid",
        _env_file=None,
    )
    with TestClient(create_app(settings)) as client:
        assert post(client, None).status_code == 503


def test_a_provider_mode_with_missing_config_fails_at_boot():
    # Eager container: a box that cannot serve its configured provider must not
    # start and then fail on the first real request.
    with pytest.raises(ValueError, match="SVC_EXAMPLE_EXAMPLE_BASE_URL"):
        create_app(
            Settings(
                provider_mode="example",
                jwt_secret=TEST_SECRET,
                example_base_url="",
                _env_file=None,
            )
        )
