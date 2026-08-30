import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.adapters.driving.http.routes import greetings, health
from app.config import Settings
from app.container import Container

logging.basicConfig(level=logging.INFO)


def create_app(settings: Settings | None = None) -> FastAPI:
    """Application factory.

    Taking settings as an argument is what makes the tests trivial: a test
    builds an app with exactly the configuration it wants, with no environment
    to set up and no module-level state to reset between cases.
    """
    settings = settings or Settings()
    container = Container(settings)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        await container.aclose()

    app = FastAPI(title="acme-svc-example", lifespan=lifespan)
    app.state.settings = settings
    app.state.container = container

    app.include_router(health.router)
    app.include_router(greetings.router)
    return app


app = create_app()
