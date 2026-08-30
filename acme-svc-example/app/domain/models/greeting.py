from pydantic import BaseModel, ConfigDict, Field


class GreetingRequest(BaseModel):
    """What the BFF asks this service to do.

    Frozen: a request object that mutates while in flight is how a retry ends
    up sending something nobody wrote.
    """

    model_config = ConfigDict(frozen=True)

    recipient: str = Field(min_length=1, max_length=120)
    locale: str = Field(default="en", min_length=2, max_length=8)
    reference: str = Field(min_length=1, max_length=64)
    """The caller's own id for this attempt.

    Echoed back on the result so a replayed delivery can be matched to the row
    that started it without the service holding any state (C-4).
    """
