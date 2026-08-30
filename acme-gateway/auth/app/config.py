from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="AUTH_", env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    # Where the issuer publishes its public keys. Reached by container name on
    # the edge network; this URL is never public.
    jwks_url: str = "http://bff:8000/api/.well-known/jwks.json"
    jwks_cache_seconds: int = 300
    # A token with an unknown `kid` triggers a refetch, because that is what a
    # key rotation looks like. It is also what a flood of forged tokens looks
    # like, so refetches are floored to this interval.
    jwks_min_refetch_seconds: int = 30

    issuer: str = "acme-bff"
    audience: str = "acme-web"

    # Copied verbatim into the upstream request. The BFF only trusts these
    # because it cannot be reached except through the gateway (C-12), and this
    # token means a compromised container on the edge network cannot forge
    # them either.
    gateway_token: str = ""

    request_timeout_seconds: float = 5.0
