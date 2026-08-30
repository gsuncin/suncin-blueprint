from enum import StrEnum


class GreetingStatus(StrEnum):
    """The verdict for one greeting attempt.

    These are *domain* statuses. A provider's own vocabulary is translated into
    them by that provider's status_map, so nothing above the adapter layer ever
    sees a provider's spelling (C-5).
    """

    DELIVERED = "DELIVERED"
    PENDING = "PENDING"
    REJECTED = "REJECTED"
    ERROR = "ERROR"
