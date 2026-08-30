"""Where the microservices are, and the keys used to reach them."""

from core.settings.env import config

# Container name on the internal Docker network. There is no public URL for
# this service and there must not be one (C-12).
EXAMPLE_SERVICE_URL = config("EXAMPLE_SERVICE_URL", default="http://svc-example:8000")
EXAMPLE_SERVICE_JWT_SECRET = config("EXAMPLE_SERVICE_JWT_SECRET", default="")
EXAMPLE_SERVICE_JWT_AUDIENCE = config("EXAMPLE_SERVICE_JWT_AUDIENCE", default="acme-svc-example")

SERVICE_REQUEST_TIMEOUT_SECONDS = config("SERVICE_REQUEST_TIMEOUT_SECONDS", default=30, cast=int)
# The token is minted per request and lives only as long as the call. A leaked
# one is useless in a minute.
SERVICE_TOKEN_TTL_SECONDS = config("SERVICE_TOKEN_TTL_SECONDS", default=60, cast=int)

# Fernet key for provider credentials at rest. One key per secret domain, never
# shared across environments: a staging leak must not decrypt production (C-3).
PROVIDER_CREDENTIAL_ENCRYPTION_KEY = config("PROVIDER_CREDENTIAL_ENCRYPTION_KEY", default="")

# Retention horizons for the provider audit log. Payloads are the sensitive,
# bulky half and go first; the metadata row survives longer because that is
# what answers "did we call them, and when".
AUDIT_PAYLOAD_RETENTION_DAYS = config("AUDIT_PAYLOAD_RETENTION_DAYS", default=30, cast=int)
AUDIT_ROW_RETENTION_DAYS = config("AUDIT_ROW_RETENTION_DAYS", default=365, cast=int)

SENTRY_DSN = config("SENTRY_DSN", default="")
SENTRY_ENVIRONMENT = config("SENTRY_ENVIRONMENT", default="local")
SENTRY_TRACES_SAMPLE_RATE = config("SENTRY_TRACES_SAMPLE_RATE", default=0.0, cast=float)
