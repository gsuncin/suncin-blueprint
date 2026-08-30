import base64
import json
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

JWKS_URL = "https://issuer.invalid/api/.well-known/jwks.json"


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class Issuer:
    """A throwaway RSA issuer, so the tests never need the real BFF."""

    def __init__(self) -> None:
        self.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        self.pem = self.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        ).decode()

    @property
    def jwk(self) -> dict:
        numbers = self.private_key.public_key().public_numbers()
        n = _b64url(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, "big"))
        e = _b64url(numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, "big"))
        thumbprint = json.dumps({"e": e, "kty": "RSA", "n": n}, separators=(",", ":"))
        import hashlib

        kid = _b64url(hashlib.sha256(thumbprint.encode()).digest())
        return {"kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid, "n": n, "e": e}

    def token(
        self,
        *,
        issuer: str = "acme-bff",
        audience: str = "acme-web",
        expires_in: int = 300,
        include_kid: bool = True,
        **claims,
    ) -> str:
        now = datetime.now(tz=timezone.utc)
        payload = {
            "iss": issuer,
            "aud": audience,
            "iat": now,
            "exp": now + timedelta(seconds=expires_in),
            "user_id": "user-1",
            "account_id": "acct-1",
            **claims,
        }
        headers = {"kid": self.jwk["kid"]} if include_kid else None
        return jwt.encode(payload, self.pem, algorithm="RS256", headers=headers)


@pytest.fixture
def issuer() -> Issuer:
    return Issuer()


@pytest.fixture
def settings() -> Settings:
    return Settings(
        jwks_url=JWKS_URL,
        gateway_token="gateway-secret",
        jwks_min_refetch_seconds=0,
        _env_file=None,
    )


@pytest.fixture
def jwks_route(issuer):
    """Stand the issuer's JWKS endpoint up in respx."""
    import httpx
    import respx

    with respx.mock(assert_all_called=False) as mock:
        mock.get(JWKS_URL).mock(
            return_value=httpx.Response(200, json={"keys": [issuer.jwk]})
        )
        yield mock


@pytest.fixture
def client(settings, jwks_route):
    with TestClient(create_app(settings)) as test_client:
        yield test_client
