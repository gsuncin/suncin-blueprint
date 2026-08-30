from fastapi import APIRouter, Depends, Header
from pydantic import SecretStr

from app.adapters.driving.http.auth import require_jwt
from app.adapters.driving.http.deps import get_say_hello
from app.adapters.driving.http.schemas.greeting_in import GreetingIn
from app.adapters.driving.http.schemas.greeting_response import GreetingResponse
from app.application.use_cases.say_hello import SayHello

router = APIRouter(prefix="/internal/greetings", dependencies=[Depends(require_jwt)])


@router.post("", response_model=GreetingResponse, response_model_by_alias=True)
async def create_greeting(
    body: GreetingIn,
    x_provider_credential: str = Header(...),
    use_case: SayHello = Depends(get_say_hello),
) -> GreetingResponse:
    """Deliver one greeting and report the verdict.

    Always 200 when the request itself was well-formed and authenticated, even
    when the provider refused — the status is in the body (C-5). That is what
    lets the BFF store a failure-marked row instead of raising (C-1).

    The credential arrives in a header and is wrapped in SecretStr here, at the
    boundary, so it cannot be logged by accident further in (C-3).
    """
    result = await use_case.execute(body.to_domain(), SecretStr(x_provider_credential))
    return GreetingResponse.from_result(result)
