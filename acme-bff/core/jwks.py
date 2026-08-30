"""Publish the public half of the signing key, so a verifier needs nothing else.

This is the seam that makes ADR-001 work: the gateway's auth service — and any
future back-end — trusts a URL, not a shared secret and not the user database.
A verifier that only holds a public key cannot mint tokens, which is exactly
the property you want when onboarding something you trust less than this
service.
"""

import base64
import hashlib
import json
from functools import lru_cache

from cryptography.hazmat.primitives import serialization
from django.conf import settings


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


@lru_cache(maxsize=1)
def public_jwk() -> dict[str, str]:
    """The signing key's public half as a JWK, with an RFC 7638 thumbprint kid.

    Deriving the public key from the private one means there is a single secret
    to configure and rotate. A separately-configured public key is a second
    thing that can silently drift out of step with the first.
    """
    private_key = serialization.load_pem_private_key(
        settings.JWT_PRIVATE_KEY.encode(), password=None
    )
    numbers = private_key.public_key().public_numbers()

    n = _b64url(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, "big"))
    e = _b64url(numbers.e.to_bytes((numbers.e.bit_length() + 7) // 8, "big"))

    # RFC 7638: the thumbprint is a hash of the canonical JWK, so the kid is
    # stable across restarts and derivable by anyone holding the same key.
    thumbprint_input = json.dumps({"e": e, "kty": "RSA", "n": n}, separators=(",", ":"))
    kid = _b64url(hashlib.sha256(thumbprint_input.encode()).digest())

    return {"kty": "RSA", "use": "sig", "alg": "RS256", "kid": kid, "n": n, "e": e}


def public_key_pem() -> str:
    private_key = serialization.load_pem_private_key(
        settings.JWT_PRIVATE_KEY.encode(), password=None
    )
    return (
        private_key.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )
