from django.db.utils import IntegrityError
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import Plan
from common.factories import make_account, make_user
from users.models import User
from users.permissions import (
    MANAGE,
    VIEW,
    ResourceArea,
    UserRole,
    get_permissions_map,
)

PASSWORD = "correct-horse-battery"


class UserModelTests(TestCase):
    def test_email_is_case_insensitively_unique(self):
        account = make_account()
        make_user(account=account, email="ada@acme.test")

        with self.assertRaises(IntegrityError):
            User.objects.create_user(
                email="ADA@acme.test", password=PASSWORD, account=account
            )

    def test_a_non_staff_user_must_have_an_account(self):
        with self.assertRaises(IntegrityError):
            User.objects.create_user(email="orphan@acme.test", password=PASSWORD)


class PermissionsMatrixTests(TestCase):
    def test_owner_can_manage_every_area(self):
        matrix = get_permissions_map(UserRole.OWNER)

        for area in ResourceArea.ALL:
            self.assertTrue(matrix[area][MANAGE], area)

    def test_a_viewer_can_read_example_but_not_change_it(self):
        matrix = get_permissions_map(UserRole.VIEWER)

        self.assertTrue(matrix[ResourceArea.EXAMPLE][VIEW])
        self.assertFalse(matrix[ResourceArea.EXAMPLE][MANAGE])

    def test_an_unknown_role_gets_nothing(self):
        # Fails closed. A role added to the enum but forgotten here must not
        # inherit someone else's permissions.
        matrix = get_permissions_map("NOT_A_ROLE")

        for area in ResourceArea.ALL:
            self.assertFalse(matrix[area][VIEW], area)
            self.assertFalse(matrix[area][MANAGE], area)

    def test_the_map_covers_every_area_for_every_role(self):
        for role in UserRole.values:
            matrix = get_permissions_map(role)
            self.assertEqual(set(matrix), set(ResourceArea.ALL), role)


class AuthFlowTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.account = make_account(plan=Plan.PRO)
        self.user = make_user(account=self.account, email="ada@acme.test", password=PASSWORD)

    def login(self):
        return self.client.post(
            reverse("token_obtain_pair"),
            {"email": "ada@acme.test", "password": PASSWORD},
            format="json",
        )

    def test_login_returns_an_access_token(self):
        response = self.login()

        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)

    def test_the_refresh_token_never_appears_in_the_body(self):
        # If it did, JavaScript could read it, and an XSS would walk away with
        # a credential that outlives the tab.
        response = self.login()

        self.assertNotIn("refresh", response.data)

    def test_the_refresh_token_is_an_httponly_cookie(self):
        response = self.login()

        cookie = response.cookies["acme_refresh"]
        self.assertTrue(cookie["httponly"])
        self.assertEqual(cookie["path"], "/api/auth")

    def test_refresh_reads_the_cookie_without_the_client_sending_it(self):
        self.login()

        response = self.client.post(reverse("token_refresh"), {}, format="json")

        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)

    def test_refresh_without_a_cookie_is_401(self):
        response = APIClient().post(reverse("token_refresh"), {}, format="json")

        self.assertEqual(response.status_code, 401)

    def test_logout_clears_the_cookie_and_blocks_reuse(self):
        self.login()

        self.client.post(reverse("token_logout"), {}, format="json")
        replay = self.client.post(reverse("token_refresh"), {}, format="json")

        self.assertEqual(replay.status_code, 401)

    def test_logged_returns_both_gate_maps(self):
        # The SPA needs them together: fetched separately they can drift out of
        # step and the UI offers something the backend then refuses.
        self.client.force_authenticate(self.user)

        response = self.client.get(reverse("auth_logged"))

        self.assertEqual(response.status_code, 200)
        self.assertIn("permissions", response.data)
        self.assertIn("entitlements", response.data)
        self.assertTrue(response.data["entitlements"]["example_jobs"])
