from django.test import TestCase

from accounts.entitlements import Entitlement, account_has, entitlements_map
from accounts.models import Plan
from common.factories import make_account


class EntitlementTests(TestCase):
    def test_a_pro_account_is_entitled(self):
        self.assertTrue(account_has(make_account(plan=Plan.PRO), Entitlement.EXAMPLE_JOBS))

    def test_a_free_account_is_not(self):
        self.assertFalse(account_has(make_account(plan=Plan.FREE), Entitlement.EXAMPLE_JOBS))

    def test_no_account_is_not_entitled(self):
        # Fails closed. "We do not know who this is" must not mean "allow it".
        self.assertFalse(account_has(None, Entitlement.EXAMPLE_JOBS))

    def test_an_unknown_plan_is_not_entitled(self):
        self.assertFalse(
            account_has(make_account(plan="ENTERPRISE_SOMEDAY"), Entitlement.EXAMPLE_JOBS)
        )

    def test_the_check_takes_no_actor(self):
        # This is what lets Celery, a management command and a webhook relay
        # reach the same verdict as an HTTP request (C-2).
        import inspect

        parameters = list(inspect.signature(account_has).parameters)
        self.assertEqual(parameters, ["account", "entitlement"])

    def test_the_map_covers_every_entitlement(self):
        self.assertEqual(
            set(entitlements_map(make_account())), set(Entitlement.ALL)
        )
