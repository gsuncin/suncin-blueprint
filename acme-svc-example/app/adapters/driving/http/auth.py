import jwt
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_bearer = HTTPBearer(auto_error=False)


async def require_jwt(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> None:
    """Verify the short-lived token the BFF mints for this call.

    Issuer and audience are both checked: a token minted for a sibling service
    must not be accepted here, or a compromised one grants more than it should.

    The claims are otherwise discarded. This token proves *who is calling*, not
    *on whose behalf* — the tenant travels in the request body, and the
    credential in a header.
    """
    settings = request.app.state.settings

    if not settings.jwt_secret:
        # Local dev and CI run the mock provider with no secret at all. Any
        # other mode with no secret is a misconfiguration, and failing closed
        # is the only safe reading of it.
        if settings.provider_mode == "mock":
            return
        raise HTTPException(
            status_code=503, detail="SVC_EXAMPLE_JWT_SECRET is not configured"
        )

    if credentials is None:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    try:
        jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=["HS256"],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
        )
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Invalid token") from None
