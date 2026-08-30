"""Endpoint tests: tenancy (C-6) and both gates (C-2), on every verb."""

import responses
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from accounts.models import Plan
from common.choices import JobStatus
from common.factories import make_account, make_record, make_user
from users.permissions import UserRole


class TenancyTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.account = make_account(name="Ours", plan=Plan.PRO)
        self.other = make_account(name="Theirs", plan=Plan.PRO)
        self.user = make_user(account=self.account, role=UserRole.MEMBER)
        self.client.force_authenticate(self.user)

    def test_the_list_shows_only_this_account(self):
        make_record(account=self.account, recipient="Ours")
        make_record(account=self.other, recipient="Theirs")

        response = self.client.get(reverse("example-record-list"))

        recipients = [row["recipient"] for row in response.data["results"]]
        self.assertEqual(recipients, ["Ours"])

    def test_another_accounts_record_is_404_not_403(self):
        # 403 would confirm the id exists, which is itself a leak.
        theirs = make_record(account=self.other)

        response = self.client.get(reverse("example-record-detail", args=[theirs.id]))

        self.assertEqual(response.status_code, 404)

    def test_create_ignores_an_account_supplied_by_the_client(self):
        response = self.client.post(
            reverse("example-record-list"),
            {"recipient": "Ada", "account": str(self.other.id)},
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        from example.models import ExampleRecord

        self.assertEqual(ExampleRecord.objects.get().account_id, self.account.id)

    def test_a_soft_deleted_record_leaves_the_list(self):
        record = make_record(account=self.account)

        self.client.delete(reverse("example-record-detail", args=[record.id]))

        response = self.client.get(reverse("example-record-list"))
        self.assertEqual(response.data["count"], 0)

    def test_delete_returns_the_row_it_archived(self):
        record = make_record(account=self.account)

        response = self.client.delete(reverse("example-record-detail", args=[record.id]))

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data["is_active"])
        record.refresh_from_db()
        self.assertFalse(record.is_active)
        self.assertIsNotNone(record.inactive_at)


class GateTests(TestCase):
    """Both gates, and the difference between them."""

    def setUp(self):
        self.client = APIClient()

    def test_anonymous_is_401(self):
        self.assertEqual(
            self.client.get(reverse("example-record-list")).status_code, 401
        )

    def test_a_viewer_can_read(self):
        user = make_user(account=make_account(plan=Plan.PRO), role=UserRole.VIEWER)
        self.client.force_authenticate(user)

        self.assertEqual(
            self.client.get(reverse("example-record-list")).status_code, 200
        )

    def test_a_viewer_cannot_write(self):
        user = make_user(account=make_account(plan=Plan.PRO), role=UserRole.VIEWER)
        self.client.force_authenticate(user)

        response = self.client.post(
            reverse("example-record-list"), {"recipient": "Ada"}, format="json"
        )

        self.assertEqual(response.status_code, 403)

    def test_an_unentitled_plan_says_so_instead_of_forbidden(self):
        # The two denials have different fixes — buy a plan, or ask an admin —
        # so they must be distinguishable by the client (C-2).
        user = make_user(account=make_account(plan=Plan.FREE), role=UserRole.OWNER)
        self.client.force_authenticate(user)

        response = self.client.post(
            reverse("example-record-list"), {"recipient": "Ada"}, format="json"
        )

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data["detail"].code, "PLAN_NOT_ENTITLED")

    def test_an_unentitled_plan_can_still_read(self):
        # Losing entitlement must not hide the data already created under it.
        account = make_account(plan=Plan.FREE)
        make_record(account=account)
        self.client.force_authenticate(make_user(account=account, role=UserRole.OWNER))

        self.assertEqual(
            self.client.get(reverse("example-record-list")).status_code, 200
        )

    def test_a_view_without_a_resource_area_is_denied(self):
        from rest_framework.test import APIRequestFactory

        from users.permissions import HasFeaturePermission

        request = APIRequestFactory().get("/")
        request.user = make_user(account=make_account(), role=UserRole.OWNER)

        self.assertFalse(HasFeaturePermission().has_permission(request, object()))


@override_settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY="")
class DeliverActionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.account = make_account(plan=Plan.PRO)
        self.client.force_authenticate(make_user(account=self.account, role=UserRole.MEMBER))
        self.record = make_record(account=self.account)

    @responses.activate
    def test_a_provider_failure_is_200_with_a_marked_row(self):
        # Not a 502: the domain has already absorbed the failure, and making
        # the client handle it again is exactly what C-1 exists to prevent.
        import requests

        responses.add(
            responses.POST, "http://svc-example:8000/internal/greetings",
            body=requests.ConnectionError("refused"),
        )

        response = self.client.post(
            reverse("example-record-deliver", args=[self.record.id])
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], JobStatus.ERROR)
        self.assertEqual(response.data["error_code"], "SERVICE_UNREACHABLE")
