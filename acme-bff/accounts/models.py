from django.db import models

from common.models import BaseModelMixin


class Plan(models.TextChoices):
    FREE = "FREE", "Free"
    PRO = "PRO", "Pro"


class Account(BaseModelMixin):
    """The tenant. Every row that belongs to a customer points at one."""

    name = models.CharField(max_length=180)
    plan = models.CharField(max_length=32, choices=Plan.choices, default=Plan.FREE)

    # Fernet ciphertext, written by core.crypto and decrypted only in
    # example/services.py::_live_credential. Never serialized, never in the
    # admin, never logged (C-3). Blank means this account has not connected a
    # provider yet, which is a normal state and not an error.
    provider_credential_encrypted = models.TextField(blank=True, default="")

    def __str__(self) -> str:
        return self.name
