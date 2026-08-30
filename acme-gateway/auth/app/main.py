"""The forwardAuth service.

Traefik calls /verify before forwarding a request upstream. A 2xx means allow,
and Traefik copies the headers named in its `authResponseHeaders` onto the
upstream request. Anything else is returned to the client as-is.

This service is the reason the BFF can trust X-Auth-* headers: Traefik strips
whatever the client sent and replaces it with what this service returns.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, Request
from fastapi.responses import JSONResponse, Response

from app.config import Settings
from app.jwks import JwksCache, JwksUnavailable
from app.verify import InvalidToken, verify_token

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    cache = JwksCache(
        settings.jwks_url,
        cache_seconds=settings.jwks_cache_seconds,
        min_refetch_seconds=settings.jwks_min_refetch_seconds,
        timeout=settings.request_timeout_seconds,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        # Deliberately no warm-up fetch. The issuer may still be starting, and
        # failing to boot because of that would make the gateway depend on
        # start order — the first request fetches instead.
        yield

    app = FastAPI(title="acme-auth", lifespan=lifespan)
    app.state.settings = settings
    app.state.jwks = cache

    def _identity_headers(claims: dict) -> dict[str, str]:
        headers = {
            "X-Auth-User-Id": str(claims.get("user_id", "")),
            "X-Auth-Account-Id": str(claims.get("account_id", "")),
            "X-Auth-Scopes": " ".join(claims.get("scopes", [])),
        }
        if settings.gateway_token:
            headers["X-Gateway-Token"] = settings.gateway_token
        return headers

    async def _verify(authorization: str | None) -> Response:
        if not authorization or not authorization.lower().startswith("bearer "):
            return JSONResponse({"detail": "Missing bearer token"}, status_code=401)

        try:
            claims = await verify_token(authorization.split(" ", 1)[1], cache, settings)
        except InvalidToken as exc:
            return JSONResponse({"detail": str(exc)}, status_code=401)
        except JwksUnavailable as exc:
            # 503, not 401: the caller may well be authorised and we cannot
            # tell. Answering 401 would log every user out during an issuer
            # outage and hide the real fault.
            logger.error("Cannot verify tokens: %s", exc)
            return JSONResponse({"detail": "Verification unavailable"}, status_code=503)

        return Response(status_code=200, headers=_identity_headers(claims))

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/verify")
    async def verify(authorization: str | None = Header(default=None)) -> Response:
        """The gate for the authenticated application."""
        return await _verify(authorization)

    @app.get("/verify/scoped")
    async def verify_scoped(
        authorization: str | None = Header(default=None),
        x_required_scope: str | None = Header(default=None),
    ) -> Response:
        """The gate for the third-party API.

        Same signature check, plus a scope the router names. A machine token is
        not a user token with extra steps: it must carry an explicit grant, or
        every integration gets everything its owner can do.
        """
        response = await _verify(authorization)
        if response.status_code != 200:
            return response

        granted = (response.headers.get("X-Auth-Scopes") or "").split()
        if x_required_scope and x_required_scope not in granted:
            return JSONResponse(
                {"detail": f"Token lacks required scope {x_required_scope}"},
                status_code=403,
            )
        return response

    return app


app = create_app()
