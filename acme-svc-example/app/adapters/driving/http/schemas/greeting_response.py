from app.adapters.driving.http.schemas.base import CamelModel
from app.domain.enums import GreetingStatus
from app.domain.models import GreetingResult


class GreetingResponse(CamelModel):
    status: GreetingStatus
    reference: str
    message: str | None = None
    provider_reference: str | None = None
    error_code: str | None = None
    error_message: str | None = None

    @classmethod
    def from_result(cls, result: GreetingResult) -> "GreetingResponse":
        return cls(**result.model_dump())
