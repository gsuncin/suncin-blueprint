"""Fetch and cache the issuer's public keys.

This service holds no key material of its own and cannot mint a token — it can
only check one. That asymmetry is the reason a second back-end can be added
later by trusting a URL rather than by being handed a shared secret (ADR-001).
"""

import logging
import time

import httpx
import jwt

logger = logging.getLogger(__name__)


class JwksUnavailable(Exception):
    """The issuer's keys could not be fetched, so nothing can be verified.

    This is an outage on our side of the fence, not a verdict on the token —
    the caller may well be authorised and we simply cannot tell. It maps to
    503, never 401.
    """


class UnknownKey(Exception):
    """We fetched the keys successfully and none of them signed this token.

    That IS a verdict: the token was not issued by the party we trust. Maps to
    401. Telling this apart from JwksUnavailable is what stops an issuer
    outage from looking like a wave of forged tokens, and vice versa.
    """


class JwksCache:
    def __init__(self, url: str, *, cache_seconds: int, min_refetch_seconds: int, timeout: float):
        self._url = url
        self._cache_seconds = cache_seconds
        self._min_refetch_seconds = min_refetch_seconds
        self._timeout = timeout
        self._keys: dict[str, object] = {}
        self._fetched_at = 0.0
        self._last_attempt = 0.0

    async def key_for(self, kid: str | None):
        """Return a verifying key, refetching when the kid is unknown.

        A `kid` we have never seen is what a key rotation looks like from here,
        so it forces a refetch — but it is also what a flood of forged tokens
        looks like, so refetches are rate-limited. Without that floor, one bad
        client turns into a denial of service against the issuer.
        """
        if self._is_stale():
            await self._refresh()

        if kid and kid not in self._keys and self._may_refetch():
            logger.info("Unknown kid %s; refetching JWKS", kid)
            await self._refresh()

        if not self._keys:
            raise JwksUnavailable("No verifying keys are available")

        if kid:
            key = self._keys.get(kid)
            if key is None:
                raise UnknownKey(f"No published key matches kid {kid}")
            return [key]

        # No kid in the header: try every key. Correct during a rotation, when
        # two keys are published and either may have signed the token.
        return list(self._keys.values())

    def _is_stale(self) -> bool:
        return not self._keys or (time.monotonic() - self._fetched_at) > self._cache_seconds

    def _may_refetch(self) -> bool:
        return (time.monotonic() - self._last_attempt) > self._min_refetch_seconds

    async def _refresh(self) -> None:
        self._last_attempt = time.monotonic()
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.get(self._url)
                response.raise_for_status()
                document = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            # Keep serving from a stale cache if we have one: a brief issuer
            # outage should not log every user out.
            logger.warning("Could not refresh JWKS: %s", exc)
            if not self._keys:
                raise JwksUnavailable(f"Could not fetch JWKS: {exc}") from exc
            return

        keys = {}
        for entry in document.get("keys", []):
            try:
                keys[entry["kid"]] = jwt.PyJWK(entry).key
            except Exception:
                logger.warning("Skipping unusable JWK %s", entry.get("kid"))

        if keys:
            self._keys = keys
            self._fetched_at = time.monotonic()
