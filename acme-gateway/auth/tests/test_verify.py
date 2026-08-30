import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from tests.conftest import JWKS_URL, Issuer


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_a_valid_token_is_allowed(client, issuer):
    response = client.get("/verify", headers=bearer(issuer.token()))

    assert response.status_code == 200


def test_identity_headers_are_returned_for_traefik_to_copy(client, issuer):
    response = client.get("/verify", headers=bearer(issuer.token()))

    assert response.headers["X-Auth-User-Id"] == "user-1"
    assert response.headers["X-Auth-Account-Id"] == "acct-1"
    assert response.headers["X-Gateway-Token"] == "gateway-secret"


def test_a_missing_token_is_401(client):
    assert client.get("/verify").status_code == 401


def test_a_non_bearer_scheme_is_401(client):
    assert client.get("/verify", headers={"Authorization": "Basic abc"}).status_code == 401


def test_garbage_is_401_not_500(client):
    assert client.get("/verify", headers=bearer("not-a-jwt")).status_code == 401


def test_an_expired_token_is_401(client, issuer):
    assert client.get("/verify", headers=bearer(issuer.token(expires_in=-30))).status_code == 401


def test_a_token_from_another_issuer_is_401(client, issuer):
    token = issuer.token(issuer="somebody-else")

    assert client.get("/verify", headers=bearer(token)).status_code == 401


def test_a_token_for_another_audience_is_401(client, issuer):
    # This is the boundary a gateway exists to hold: a token minted for a
    # different consumer of the same issuer is not valid here.
    token = issuer.token(audience="some-other-app")

    assert client.get("/verify", headers=bearer(token)).status_code == 401


def test_a_token_signed_by_a_different_key_is_401(client):
    imposter = Issuer()

    assert client.get("/verify", headers=bearer(imposter.token())).status_code == 401


def test_a_token_without_a_kid_still_verifies(client, issuer):
    # Not every issuer sets kid. Trying each published key is also what is
    # needed mid-rotation, when either of two keys may have signed the token.
    token = issuer.token(include_kid=False)

    assert client.get("/verify", headers=bearer(token)).status_code == 200


def test_an_unknown_kid_triggers_a_refetch(settings, issuer):
    rotated = Issuer()
    calls = {"n": 0}

    def jwks(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        # The rotated key only appears on the second fetch, which is exactly
        # what a key rotation looks like from here.
        keys = [issuer.jwk] if calls["n"] == 1 else [issuer.jwk, rotated.jwk]
        return httpx.Response(200, json={"keys": keys})

    with respx.mock(assert_all_called=False) as mock:
        mock.get(JWKS_URL).mock(side_effect=jwks)
        with TestClient(create_app(settings)) as client:
            assert client.get("/verify", headers=bearer(issuer.token())).status_code == 200
            assert client.get("/verify", headers=bearer(rotated.token())).status_code == 200

    assert calls["n"] == 2


def test_refetching_is_rate_limited(issuer):
    # A flood of forged tokens with random kids must not turn into a denial of
    # service against the issuer.
    settings = Settings(jwks_url=JWKS_URL, jwks_min_refetch_seconds=3600, _env_file=None)
    calls = {"n": 0}

    def jwks(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        return httpx.Response(200, json={"keys": [issuer.jwk]})

    with respx.mock(assert_all_called=False) as mock:
        mock.get(JWKS_URL).mock(side_effect=jwks)
        with TestClient(create_app(settings)) as client:
            for _ in range(5):
                client.get("/verify", headers=bearer(Issuer().token()))

    assert calls["n"] == 1


def test_an_unreachable_issuer_is_503_not_401(settings):
    # 401 would log every user out during an issuer outage and hide the real
    # fault. The caller may well be authorised; we simply cannot tell.
    with respx.mock(assert_all_called=False) as mock:
        mock.get(JWKS_URL).mock(side_effect=httpx.ConnectError("refused"))
        with TestClient(create_app(settings)) as client:
            response = client.get("/verify", headers=bearer(Issuer().token()))

    assert response.status_code == 503


def test_a_stale_cache_survives_a_brief_issuer_outage(settings, issuer):
    calls = {"n": 0}

    def jwks(request: httpx.Request) -> httpx.Response:
        calls["n"] += 1
        if calls["n"] == 1:
            return httpx.Response(200, json={"keys": [issuer.jwk]})
        raise httpx.ConnectError("refused")

    with respx.mock(assert_all_called=False) as mock:
        mock.get(JWKS_URL).mock(side_effect=jwks)
        with TestClient(create_app(settings)) as client:
            assert client.get("/verify", headers=bearer(issuer.token())).status_code == 200
            # Unknown kid forces a refetch that fails; the cached key must
            # still serve the tokens it can verify.
            client.get("/verify", headers=bearer(Issuer().token()))
            assert client.get("/verify", headers=bearer(issuer.token())).status_code == 200


def test_no_gateway_token_configured_means_none_is_sent(issuer, jwks_route):
    settings = Settings(jwks_url=JWKS_URL, gateway_token="", _env_file=None)

    with TestClient(create_app(settings)) as client:
        response = client.get("/verify", headers=bearer(issuer.token()))

    assert response.status_code == 200
    assert "X-Gateway-Token" not in response.headers


class TestScopedVerification:
    """The third-party gate: a machine token must carry an explicit grant."""

    def test_a_token_with_the_required_scope_is_allowed(self, client, issuer):
        token = issuer.token(scopes=["records:read", "records:write"])

        response = client.get(
            "/verify/scoped",
            headers={**bearer(token), "X-Required-Scope": "records:read"},
        )

        assert response.status_code == 200
        assert response.headers["X-Auth-Scopes"] == "records:read records:write"

    def test_a_token_without_the_scope_is_403_not_401(self, client, issuer):
        # 401 means "who are you"; 403 means "I know who you are and this is
        # not yours". An integration owner needs to be able to tell them apart.
        token = issuer.token(scopes=["records:read"])

        response = client.get(
            "/verify/scoped",
            headers={**bearer(token), "X-Required-Scope": "records:write"},
        )

        assert response.status_code == 403

    def test_a_token_with_no_scopes_at_all_is_refused(self, client, issuer):
        response = client.get(
            "/verify/scoped",
            headers={**bearer(issuer.token()), "X-Required-Scope": "records:read"},
        )

        assert response.status_code == 403

    def test_an_invalid_token_is_still_401(self, client):
        response = client.get(
            "/verify/scoped",
            headers={**bearer("garbage"), "X-Required-Scope": "records:read"},
        )

        assert response.status_code == 401
