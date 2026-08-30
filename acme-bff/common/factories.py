"""Small builders for tests. Not a fixtures framework — just the four calls
every test needs, so no test has to remember that a non-staff user without an
account violates a constraint.
"""

from accounts.models import Account, Plan
from example.models import ExampleRecord
from users.models import User
from users.permissions import UserRole


def make_account(*, name: str = "Acme", plan: str = Plan.PRO) -> Account:
    return Account.objects.create(name=name, plan=plan)


def make_user(
    *,
    account: Account | None = None,
    email: str = "member@acme.test",
    role: str = UserRole.MEMBER,
    password: str = "correct-horse-battery",
    **extra,
) -> User:
    return User.objects.create_user(
        email=email,
        password=password,
        account=account if account is not None else make_account(),
        role=role,
        **extra,
    )


def make_record(*, account: Account, recipient: str = "Ada", **extra) -> ExampleRecord:
    return ExampleRecord.objects.create(account=account, recipient=recipient, **extra)
