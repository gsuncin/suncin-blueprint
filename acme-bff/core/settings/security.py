"""Secrets, transport security, and the identity the gateway validates."""

import base64
from datetime import timedelta

from decouple import Csv

from core.settings.env import config

DEBUG = config("DEBUG", default=False, cast=bool)
SECRET_KEY = config("SECRET_KEY", default="insecure-dev-key" if DEBUG else "")
ALLOWED_HOSTS = config("ALLOWED_HOSTS", default="*" if DEBUG else "", cast=Csv())
CSRF_TRUSTED_ORIGINS = config("CSRF_TRUSTED_ORIGINS", default="", cast=Csv())

# Every one of these defaults to "on unless DEBUG", so a box that forgets to
# set them is secure rather than open.
SECURE_SSL_REDIRECT = config("SECURE_SSL_REDIRECT", default=not DEBUG, cast=bool)
SECURE_HSTS_SECONDS = config("SECURE_HSTS_SECONDS", default=0 if DEBUG else 31536000, cast=int)
SECURE_HSTS_INCLUDE_SUBDOMAINS = not DEBUG
# Off by default, and `check --deploy` will warn about that. It is a deliberate
# choice: preloading is submitted to a browser-vendor list and removal takes
# months, so it is opted into per deployment, not inherited from a template.
SECURE_HSTS_PRELOAD = config("SECURE_HSTS_PRELOAD", default=False, cast=bool)
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
# The gateway terminates TLS. Without this Django believes every request is
# plain HTTP and SECURE_SSL_REDIRECT loops forever.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# --- Identity ---------------------------------------------------------------
# This service is the ISSUER. The gateway's auth service is a verifier and
# holds only the public half, which is the whole reason a second back-end can
# be added later without touching the user database (ADR-001).
#
# The PEM is base64-encoded into a single line so it survives a .env file, a
# Terraform variable, and a cloud-init env file without newline mangling.
_private_key_b64 = config("JWT_PRIVATE_KEY_B64", default="")

if _private_key_b64:
    JWT_PRIVATE_KEY = base64.b64decode(_private_key_b64).decode()
elif DEBUG:
    # Generated per process. Fine for `runserver` and the test suite, both of
    # which are single-process. It is NOT fine under gunicorn with two workers:
    # tokens minted by one would be rejected by the other. Hence the hard
    # failure below when DEBUG is off.
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    JWT_PRIVATE_KEY = (
        rsa.generate_private_key(public_exponent=65537, key_size=2048)
        .private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
        .decode()
    )
else:
    raise ValueError(
        "JWT_PRIVATE_KEY_B64 is required when DEBUG is off. Run `make keys`."
    )

# Derived from the private key rather than configured separately, so there is
# exactly one secret to rotate rather than a pair that can silently drift apart.
def _public_key_pem(private_pem: str) -> str:
    from cryptography.hazmat.primitives import serialization

    return (
        serialization.load_pem_private_key(private_pem.encode(), password=None)
        .public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )


SIMPLE_JWT = {
    "ALGORITHM": "RS256",
    "SIGNING_KEY": JWT_PRIVATE_KEY,
    "VERIFYING_KEY": _public_key_pem(JWT_PRIVATE_KEY),
    "ISSUER": config("JWT_ISSUER", default="acme-bff"),
    "AUDIENCE": config("JWT_AUDIENCE", default="acme-web"),
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=config("ACCESS_TOKEN_MINUTES", default=15, cast=int)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=config("REFRESH_TOKEN_DAYS", default=1, cast=int)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "user_id",
}

# The refresh token is never handed to JavaScript. It lives in an HttpOnly
# cookie so an XSS cannot exfiltrate a long-lived credential; the access token
# is short-lived and kept in memory only.
AUTH_REFRESH_COOKIE_NAME = config("AUTH_REFRESH_COOKIE_NAME", default="acme_refresh")
AUTH_REFRESH_COOKIE_PATH = config("AUTH_REFRESH_COOKIE_PATH", default="/api/auth")
AUTH_REFRESH_COOKIE_DOMAIN = config("AUTH_REFRESH_COOKIE_DOMAIN", default=None)
AUTH_REFRESH_COOKIE_SECURE = config("AUTH_REFRESH_COOKIE_SECURE", default=not DEBUG, cast=bool)
AUTH_REFRESH_COOKIE_SAMESITE = config("AUTH_REFRESH_COOKIE_SAMESITE", default="Lax")

# --- Trusting the gateway ---------------------------------------------------
# The gateway strips any client-supplied X-Auth-* and injects its own. This
# service is unreachable except through it (C-12), but network position alone
# would also be enough for anything else on the edge network, so the gateway
# sends a shared token as well.
#
# Empty means "do not trust identity headers at all", which is the correct
# default: the JWT in the Authorization header is verified here regardless.
GATEWAY_TOKEN = config("GATEWAY_TOKEN", default="")
