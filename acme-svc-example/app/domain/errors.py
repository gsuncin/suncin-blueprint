class DomainError(Exception):
    """Base for everything this service raises on purpose."""


class ProviderError(DomainError):
    """A provider failed in a way the use case can turn into a verdict.

    `retryable` is the provider's answer to "would trying again plausibly
    work?" — a timeout is retryable, a malformed request is not. The caller
    uses it to decide whether a sweep should pick the record up again.
    """

    def __init__(self, code: str, message: str, *, retryable: bool = False) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message
        self.retryable = retryable


class ProviderNotConfiguredError(DomainError):
    """The caller's credential is missing, malformed, or rejected outright.

    Distinct from ProviderError because it is a fact about the *caller's*
    configuration, not about the provider being unwell.
    """
