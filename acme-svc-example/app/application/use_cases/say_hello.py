import logging

from pydantic import SecretStr

from app.application.ports import GreetingProviderPort
from app.domain.errors import ProviderError, ProviderNotConfiguredError
from app.domain.models import GreetingRequest, GreetingResult

logger = logging.getLogger(__name__)


class SayHello:
    """Deliver a greeting through whichever provider is wired in.

    Folds every provider failure into a result object, so the driving adapter
    can answer HTTP 200 with a verdict rather than an error code (C-5). This is
    the reason the BFF can follow C-1: it always gets a row back.
    """

    def __init__(self, provider: GreetingProviderPort) -> None:
        self._provider = provider

    async def execute(
        self, request: GreetingRequest, credential: SecretStr
    ) -> GreetingResult:
        try:
            return await self._provider.deliver_greeting(request, credential)
        except ProviderNotConfiguredError as exc:
            return GreetingResult.failed(
                request.reference, "PROVIDER_NOT_CONFIGURED", str(exc)
            )
        except ProviderError as exc:
            return GreetingResult.failed(request.reference, exc.code, exc.message)
        except Exception:
            # Deliberately broad. An unexpected provider bug must not become a
            # 500 that the BFF has to special-case — it becomes a verdict like
            # any other, and the stack trace goes to the log.
            logger.exception(
                "Unexpected provider failure delivering greeting %s", request.reference
            )
            return GreetingResult.failed(
                request.reference, "PROVIDER_ERROR", "Unexpected provider failure"
            )
