from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.db.models.functions import Lower

from common.models import BaseModelMixin
from users.permissions import UserRole


class UserManager(BaseUserManager):
    """Email is the login. `username` does not exist on this model."""

    use_in_migrations = True

    def _create_user(self, email: str, password: str | None, **extra):
        if not email:
            raise ValueError("An email address is required")
        user = self.model(email=self.normalize_email(email), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email: str, password: str | None = None, **extra):
        extra.setdefault("is_staff", False)
        extra.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra)

    def create_superuser(self, email: str, password: str | None = None, **extra):
        extra.setdefault("is_staff", True)
        extra.setdefault("is_superuser", True)
        extra.setdefault("role", UserRole.OWNER)
        return self._create_user(email, password, **extra)


class User(AbstractUser, BaseModelMixin):
    username = None
    email = models.EmailField(unique=True)
    role = models.CharField(max_length=32, choices=UserRole.choices, default=UserRole.MEMBER)
    account = models.ForeignKey(
        "accounts.Account", on_delete=models.CASCADE, null=True, blank=True,
        related_name="users",
    )

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    objects = UserManager()

    class Meta:
        constraints = [
            # A non-staff user with no account has no tenant to be scoped to,
            # and every queryset filter would silently match nothing.
            models.CheckConstraint(
                condition=models.Q(is_staff=True) | models.Q(account__isnull=False),
                name="user_has_account_unless_staff",
            ),
            # Postgres is case-sensitive; email addresses are not. Without this
            # "Ada@x.com" and "ada@x.com" are two accounts.
            models.UniqueConstraint(Lower("email"), name="user_email_ci_unique"),
        ]

    def __str__(self) -> str:
        return self.email
