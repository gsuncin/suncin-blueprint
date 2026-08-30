"""HTTP transport for the example provider, and the single place where its
failures become domain errors.

Every other module in this package can assume it is handed a parsed body or a
ProviderError — nothing else deals in status codes.
"""

import logging
from typing import Any

import httpx
from pydantic import SecretStr

from app.domain.errors import ProviderError, ProviderNotConfiguredError

logger = logging.getLogger(__name__)

REDACTED = "[REDACTED]"


class ExampleClient:
    def __init__(self, base_url: str, timeout_seconds: float) -> None:
        self._client = httpx.AsyncClient(base_url=base_url, timeout=timeout_seconds)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def post(
        self, path: str, payload: dict[str, Any], credential: SecretStr
    ) -> dict[str, Any]:
        try:
            response = await self._client.post(
                path,
                json=payload,
                headers={"Authorization": f"Bearer {credential.get_secret_value()}"},
            )
        except httpx.TimeoutException as exc:
            raise ProviderError(
                "PROVIDER_TIMEOUT", f"Provider timed out: {exc}", retryable=True
            ) from exc
        except httpx.HTTPError as exc:
            raise ProviderError(
                "PROVIDER_UNAVAILABLE", f"Provider unreachable: {exc}", retryable=True
            ) from exc

        if response.status_code in (401, 403):
            # Their problem or ours, but not a transient one: retrying with the
            # same credential will fail identically.
            raise ProviderNotConfiguredError("Provider rejected the credential")

        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderError(
                "PROVIDER_UNAVAILABLE",
                f"Provider returned {response.status_code}",
                retryable=True,
            )

        if response.status_code >= 400:
            raise ProviderError(
                "PROVIDER_REJECTED", self._safe_error_text(response), retryable=False
            )

        try:
            return response.json()
        except ValueError as exc:
            raise ProviderError(
                "PROVIDER_MALFORMED_RESPONSE",
                "Provider returned a body that is not JSON",
            ) from exc

    @staticmethod
    def _safe_error_text(response: httpx.Response) -> str:
        """Providers echo the request back in error bodies, credential included.

        Scrub before this text reaches a log, an exception message, or the
        error_message column the BFF will store (C-3).
        """
        text = response.text[:500]
        for marker in ("Bearer ", "authorization", "Authorization"):
            if marker in text:
                return f"Provider returned {response.status_code} {REDACTED}"
        return f"Provider returned {response.status_code}: {text}"
