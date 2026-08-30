import logging

from app.application.ports import GreetingProviderPort
from app.config import Settings

logger = logging.getLogger(__name__)


class Container:
    """Composition root: builds provider adapters from settings.

    Eager on purpose. A box configured for a provider this build cannot serve
    must fail at startup, not on the first request someone makes.

    This is the ONLY module outside adapters/driven/providers/ allowed to name
    a provider (C-5).
    """

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._client = None

        if settings.provider_mode == "example":
            self._wire_example(settings)
            return

        from app.adapters.driven.providers.mock.adapter import MockProvider

        logger.info("Wiring the mock greeting provider")
        self.greeting_provider: GreetingProviderPort = MockProvider()

    def _wire_example(self, settings: Settings) -> None:
        # Imports are local to the branch so a build that will never run this
        # provider does not pay to import it, and a broken optional dependency
        # cannot break mock mode.
        from app.adapters.driven.providers.example.client import ExampleClient
        from app.adapters.driven.providers.example.greeting_adapter import (
            ExampleGreetingAdapter,
        )

        missing = [
            f"SVC_EXAMPLE_{name.upper()}"
            for name in ("example_base_url",)
            if not getattr(settings, name)
        ]
        if missing:
            # Names only, never values (C-3).
            raise ValueError(
                "SVC_EXAMPLE_PROVIDER_MODE=example needs " + ", ".join(missing)
            )

        self._client = ExampleClient(
            settings.example_base_url, settings.request_timeout_seconds
        )
        self.greeting_provider: GreetingProviderPort = ExampleGreetingAdapter(
            self._client
        )

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()
