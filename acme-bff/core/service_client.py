"""One way to call a microservice, so timeout, auth and audit happen once.

Every outbound call in this project goes through `ServiceClient.request`. That
is what makes it possible to state, and check, that:

  - nothing calls out without a timeout,
  - nothing calls out without being recorded,
  - a transport failure and a 4xx are told apart by the caller,
  - and a credential never reaches the audit log, because credentials travel in
    headers and this records payloads (C-3).

There is deliberately no retry loop here. A retry inside a request/response
cycle holds a worker and a database connection hostage while a provider is
already unwell. Retry is a scheduled sweep (C-4).
"""

import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
import requests
from django.conf import settings

from audit.recorder import AuditContext, record_provider_call

logger = logging.getLogger(__name__)


class ServiceError(Exception):
    """A call to an internal service failed.

    `status_code is None` means the service could not be reached at all — a DNS
    failure, a refused connection, a timeout. That distinction decides whether
    a sweep should try again, so it is worth the extra attribute.
    """

    def __init__(self, message: str, status_code: int | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code


class ServiceClient:
    """A client for one internal service."""

    def __init__(self, *, base_url: str, jwt_secret: str, audience: str) -> None:
        self._base_url = base_url.rstrip("/")
        self._jwt_secret = jwt_secret
        self._audience = audience

    def _auth_headers(self) -> dict[str, str]:
        """Mint a token that is valid for this call and no longer.

        Empty secret means local dev or CI, where the service runs its mock
        provider and accepts unauthenticated calls. In any other mode the
        service fails closed with a 503, so this cannot quietly become the
        production configuration.
        """
        if not self._jwt_secret:
            return {}

        now = datetime.now(tz=timezone.utc)
        token = jwt.encode(
            {
                "iss": settings.SIMPLE_JWT["ISSUER"],
                "aud": self._audience,
                "iat": now,
                "exp": now + timedelta(seconds=settings.SERVICE_TOKEN_TTL_SECONDS),
            },
            self._jwt_secret,
            algorithm="HS256",
        )
        return {"Authorization": f"Bearer {token}"}

    def request(
        self,
        method: str,
        path: str,
        *,
        audit: AuditContext | None,
        json: dict[str, Any] | None = None,
        params: dict[str, Any] | None = None,
        secret_headers: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """Make one call. Raises ServiceError; never returns a failure.

        `audit` has no default on purpose: declining to record a call must be a
        deliberate `None` at the call site, visible in review, rather than
        something you get by forgetting an argument.

        `secret_headers` is where live credentials go. They are merged into the
        request headers and are never passed to the recorder — this is the
        mechanism behind "secrets travel in headers, never bodies" (C-3).
        """
        url = f"{self._base_url}{path}"
        headers = {**self._auth_headers(), **(secret_headers or {})}
        started = time.monotonic()

        try:
            response = requests.request(
                method,
                url,
                json=json,
                params=params,
                headers=headers,
                timeout=settings.SERVICE_REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            record_provider_call(
                audit, method=method, path=path, request_payload=json,
                outcome=exc, started=started,
            )
            status_code = getattr(exc.response, "status_code", None)
            raise ServiceError(str(exc), status_code=status_code) from exc

        record_provider_call(
            audit, method=method, path=path, request_payload=json,
            outcome=response, started=started,
        )

        if not response.content:
            return {}
        try:
            return response.json()
        except ValueError as exc:
            raise ServiceError("Service returned a body that is not JSON") from exc
