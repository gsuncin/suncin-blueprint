from django.db import models


class JobStatus(models.TextChoices):
    """Shared by anything that hands work to an external system.

    ERROR is ours (we could not get an answer); REJECTED is theirs (they
    answered no). Collapsing them loses the only thing that decides whether a
    sweep should try again.
    """

    PENDING = "PENDING", "Pending"
    DELIVERED = "DELIVERED", "Delivered"
    REJECTED = "REJECTED", "Rejected"
    ERROR = "ERROR", "Error"

    @classmethod
    def open_statuses(cls) -> list[str]:
        return [cls.PENDING]
