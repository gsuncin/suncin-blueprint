from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from accounts.models import Account, Plan
from core.crypto import encrypt_provider_credential
from users.models import User
from users.permissions import UserRole


class Command(BaseCommand):
    """Create the minimum needed to sign in locally.

    Idempotent, so `make up` can run it every time without failing on the
    second boot. Refuses to run when DEBUG is off: a known password committed
    to a repository is a backdoor, and the only thing stopping it becoming one
    in production is this check.
    """

    help = "Create a development account and user. Local use only."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--email", default="dev@acme.test")
        parser.add_argument("--password", default="acme-dev-password")

    def handle(self, *args, **options) -> None:
        if not settings.DEBUG:
            raise CommandError("seed_dev refuses to run with DEBUG off.")

        account, created = Account.objects.get_or_create(
            name="Acme Development",
            defaults={"plan": Plan.PRO},
        )
        # The service's mock provider accepts any non-empty credential; this
        # exists so the happy path works out of the box rather than failing
        # with CREDENTIAL_UNAVAILABLE on a fresh checkout.
        if settings.PROVIDER_CREDENTIAL_ENCRYPTION_KEY and not account.provider_credential_encrypted:
            account.provider_credential_encrypted = encrypt_provider_credential(
                "dev-provider-credential"
            )
            account.save(update_fields=["provider_credential_encrypted", "updated_at"])

        self.stdout.write(f"account: {account.name} ({'created' if created else 'exists'})")

        user, created = User.objects.get_or_create(
            email=options["email"],
            defaults={
                "account": account,
                "role": UserRole.OWNER,
                "first_name": "Dev",
                "last_name": "User",
                "is_staff": True,
                "is_superuser": True,
            },
        )
        # Reset the password every run, so a forgotten local change does not
        # leave you locked out of your own dev box.
        user.set_password(options["password"])
        user.save()

        self.stdout.write(
            self.style.SUCCESS(
                f"user: {user.email} ({'created' if created else 'updated'}) "
                f"password: {options['password']}"
            )
        )
