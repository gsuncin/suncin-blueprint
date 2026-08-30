import jwt

from app.config import Settings
from app.jwks import JwksCache, UnknownKey


class InvalidToken(Exception):
    """The token is absent, malformed, expired, or not for us."""


async def verify_token(token: str, cache: JwksCache, settings: Settings) -> dict:
    """Return the claims, or raise InvalidToken.

    Audience and issuer are both checked. Without the audience check, a token
    minted for a different consumer of the same issuer would be accepted here —
    which is precisely the boundary a gateway exists to hold.
    """
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise InvalidToken(f"Malformed token: {exc}") from exc

    try:
        candidate_keys = await cache.key_for(header.get("kid"))
    except UnknownKey as exc:
        raise InvalidToken(str(exc)) from exc

    last_error: Exception | None = None
    for key in candidate_keys:
        try:
            return jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=settings.audience,
                issuer=settings.issuer,
            )
        except jwt.PyJWTError as exc:
            last_error = exc

    raise InvalidToken(f"Token rejected: {last_error}")
