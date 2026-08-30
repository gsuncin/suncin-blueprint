"""Provider status vocabulary -> domain status.

The only file that knows this provider's spelling. Nothing above the adapter
layer sees "sent" or "queued" (C-5).
"""

from app.domain.enums import GreetingStatus

_STATUS = {
    "sent": GreetingStatus.DELIVERED,
    "delivered": GreetingStatus.DELIVERED,
    "queued": GreetingStatus.PENDING,
    "accepted": GreetingStatus.PENDING,
    "refused": GreetingStatus.REJECTED,
    "blocked": GreetingStatus.REJECTED,
}


def to_domain_status(provider_status: str) -> GreetingStatus:
    """Unknown statuses become PENDING, not ERROR.

    A provider that adds a status we have not seen has not failed — treating an
    unrecognised one as an error would settle records that are still in flight.
    """
    return _STATUS.get(provider_status.lower(), GreetingStatus.PENDING)
