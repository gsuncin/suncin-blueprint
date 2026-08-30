from abc import ABC, abstractmethod

from pydantic import SecretStr

from app.domain.models import GreetingRequest, GreetingResult


class GreetingProviderPort(ABC):
    """The one thing a greeting provider must be able to do.

    Takes and returns domain models only — no wire shapes, no provider
    vocabulary. Adding a second provider must not require editing a use case;
    if it does, this port is wrong and it is the port that gets fixed (C-5).

    The credential arrives per call and is never stored: this service is
    stateless, and the BFF is the only party that persists anything (C-3).
    """

    @abstractmethod
    async def deliver_greeting(
        self, request: GreetingRequest, credential: SecretStr
    ) -> GreetingResult:
        """Deliver one greeting.

        Raises ProviderError for anything the caller should be able to turn
        into a verdict. Must not raise for a provider *rejecting* the request —
        that is a GreetingResult with status=REJECTED.
        """
