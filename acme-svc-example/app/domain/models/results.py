from pydantic import BaseModel, ConfigDict

from app.domain.enums import GreetingStatus


class GreetingResult(BaseModel):
    """The verdict, in domain terms.

    A rejection is a fact about the world, not an error in the request, so this
    travels back over HTTP 200 with `status=REJECTED` (C-5). Only auth,
    validation and bugs get a 4xx/5xx.
    """

    model_config = ConfigDict(frozen=True)

    status: GreetingStatus
    reference: str
    message: str | None = None
    provider_reference: str | None = None
    error_code: str | None = None
    error_message: str | None = None

    @classmethod
    def failed(
        cls, reference: str, error_code: str, error_message: str
    ) -> "GreetingResult":
        return cls(
            status=GreetingStatus.ERROR,
            reference=reference,
            error_code=error_code,
            error_message=error_message,
        )
