from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Every knob this service has, and where it comes from.

    The env prefix is per-service so one .env file on the box can configure
    several services without collisions.
    """

    model_config = SettingsConfigDict(
        env_prefix="SVC_EXAMPLE_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    provider_mode: Literal["mock", "example"] = "mock"

    # Inbound auth: the BFF mints a short-lived token per request. The claims
    # are discarded — the token proves caller identity only and carries no
    # tenant, because a stateless service has nothing to scope.
    jwt_secret: str = ""
    jwt_issuer: str = "acme-bff"
    jwt_audience: str = "acme-svc-example"

    # Outbound: the example provider.
    example_base_url: str = "https://greetings.example.invalid"
    request_timeout_seconds: float = 30.0
