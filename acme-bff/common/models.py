import uuid

from django.db import models
from django.utils import timezone


class BaseModelMixin(models.Model):
    """What every row in this project has.

    UUID primary keys because ids appear in URLs the client holds: sequential
    integers leak how many customers you have and make one tenant's ids
    guessable from another's.

    Soft delete because a deleted row is still the answer to "what happened to
    that?", and because a hard delete cascades in ways nobody predicts (C-7).
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_active = models.BooleanField(default=True, db_index=True)
    inactive_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        abstract = True
        ordering = ["-created_at"]

    def deactivate(self, *, save: bool = True) -> None:
        self.is_active = False
        self.inactive_at = timezone.now()
        if save:
            self.save(update_fields=["is_active", "inactive_at", "updated_at"])
