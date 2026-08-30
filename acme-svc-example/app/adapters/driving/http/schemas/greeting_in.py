from pydantic import Field

from app.adapters.driving.http.schemas.base import CamelModel
from app.domain.models import GreetingRequest


class GreetingIn(CamelModel):
    recipient: str = Field(min_length=1, max_length=120)
    locale: str = Field(default="en", min_length=2, max_length=8)
    reference: str = Field(min_length=1, max_length=64)

    def to_domain(self) -> GreetingRequest:
        return GreetingRequest(
            recipient=self.recipient, locale=self.locale, reference=self.reference
        )
