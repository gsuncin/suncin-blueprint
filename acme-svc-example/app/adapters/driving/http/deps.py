from fastapi import Request

from app.application.use_cases.say_hello import SayHello


def get_say_hello(request: Request) -> SayHello:
    return SayHello(request.app.state.container.greeting_provider)
