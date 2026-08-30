"""The C-1 contract: these functions never raise, they mark the row."""

from unittest.mock import patch

import requests
import responses
from django.test import TestCase, override_settings
from django.utils import timezone

from accounts.models import Plan
from audit.models import ProviderCall
from common.choices import JobStatus
from common.factories import make_account, make_record
from example.services import apply_delivery_result, deliver_example_record

SERVICE_URL = "http://svc-example:8000/internal/greetings"


@override_settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY="")
class DeliveryTests(TestCase):
    def setUp(self):
        self.account = make_account(plan=Plan.PRO)
        self.record = make_record(account=self.account)

    @responses.activate
    def test_a_delivered_verdict_settles_the_row(self):
        responses.add(
            responses.POST, SERVICE_URL,
            json={"status": "DELIVERED", "message": "Hello, Ada!",
                  "providerReference": "mock-1", "reference": str(self.record.id)},
            status=200,
        )

        result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.DELIVERED)
        self.assertEqual(result.message, "Hello, Ada!")
        self.assertIsNotNone(result.delivered_at)

    @responses.activate
    def test_an_unreachable_service_marks_the_row_and_does_not_raise(self):
        responses.add(
            responses.POST, SERVICE_URL, body=requests.ConnectionError("refused")
        )

        result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.ERROR)
        self.assertEqual(result.error_code, "SERVICE_UNREACHABLE")
        self.assertIsNone(result.delivered_at)

    @responses.activate
    def test_a_service_500_is_distinguished_from_being_unreachable(self):
        # The distinction decides whether the sweep should try again.
        responses.add(responses.POST, SERVICE_URL, json={"detail": "boom"}, status=500)

        result = deliver_example_record(self.record)

        self.assertEqual(result.error_code, "SERVICE_ERROR")

    @responses.activate
    def test_a_rejection_is_recorded_as_rejected_not_as_our_error(self):
        responses.add(
            responses.POST, SERVICE_URL,
            json={"status": "REJECTED", "errorCode": "RECIPIENT_REJECTED",
                  "errorMessage": "blocked", "reference": str(self.record.id)},
            status=200,
        )

        result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.REJECTED)
        self.assertEqual(result.error_code, "RECIPIENT_REJECTED")

    def test_an_unentitled_account_is_blocked_in_the_service_layer(self):
        # The DRF permission class never runs on the sweep or a management
        # command. If the gate lived only there, this path would be free (C-2).
        record = make_record(account=make_account(plan=Plan.FREE))

        result = deliver_example_record(record)

        self.assertEqual(result.status, JobStatus.ERROR)
        self.assertEqual(result.error_code, "PLAN_NOT_ENTITLED")

    @responses.activate
    def test_an_unexpected_exception_still_returns_a_row(self):
        with patch("example.services._live_credential", side_effect=RuntimeError("boom")):
            result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.ERROR)
        self.assertEqual(result.error_code, "UNEXPECTED_ERROR")

    @responses.activate
    def test_the_credential_travels_in_a_header_never_the_body(self):
        responses.add(
            responses.POST, SERVICE_URL,
            json={"status": "DELIVERED", "reference": str(self.record.id)}, status=200,
        )

        deliver_example_record(self.record)

        request = responses.calls[0].request
        self.assertIn("X-Provider-Credential", request.headers)
        self.assertNotIn("credential", request.body.decode())

    @responses.activate
    def test_the_audited_payload_does_not_contain_the_credential(self):
        # This is the whole reason for the header/body split: the recorder logs
        # payloads and never headers (C-3).
        responses.add(
            responses.POST, SERVICE_URL,
            json={"status": "DELIVERED", "reference": str(self.record.id)}, status=200,
        )

        deliver_example_record(self.record)

        call = ProviderCall.objects.get()
        self.assertNotIn("credential", str(call.request_payload))
        self.assertEqual(call.service, "acme-svc-example")

    @responses.activate
    def test_a_failed_call_is_still_audited(self):
        responses.add(responses.POST, SERVICE_URL, body=requests.ConnectionError("x"))

        deliver_example_record(self.record)

        call = ProviderCall.objects.get()
        self.assertFalse(call.succeeded)


@override_settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY="")
class IdempotencyTests(TestCase):
    """C-4: a replayed verdict must not settle the record twice."""

    def setUp(self):
        self.record = make_record(account=make_account(plan=Plan.PRO))

    def test_a_replayed_verdict_does_not_move_the_settled_timestamp(self):
        payload = {"status": "DELIVERED", "message": "Hello!", "providerReference": "p-1"}

        first = apply_delivery_result(self.record, payload)
        settled_at = first.delivered_at
        second = apply_delivery_result(self.record, payload)

        self.assertEqual(second.delivered_at, settled_at)

    def test_a_stale_event_cannot_un_settle_a_delivered_record(self):
        apply_delivery_result(self.record, {"status": "DELIVERED"})

        result = apply_delivery_result(self.record, {"status": "PENDING"})

        self.assertEqual(result.status, JobStatus.DELIVERED)
        self.assertIsNotNone(result.delivered_at)

    @responses.activate
    def test_an_already_delivered_record_makes_no_second_call(self):
        self.record.delivered_at = timezone.now()
        self.record.status = JobStatus.DELIVERED
        self.record.save()

        deliver_example_record(self.record)

        self.assertEqual(len(responses.calls), 0)


@override_settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY="")
class SweepTests(TestCase):
    @responses.activate
    def test_the_sweep_retries_only_records_awaiting_a_verdict(self):
        from django.core.management import call_command

        account = make_account(plan=Plan.PRO)
        pending = make_record(account=account, recipient="Pending")
        settled = make_record(account=account, recipient="Settled")
        apply_delivery_result(settled, {"status": "DELIVERED"})

        responses.add(
            responses.POST, SERVICE_URL,
            json={"status": "DELIVERED", "reference": str(pending.id)}, status=200,
        )

        call_command("sweep_example_jobs", quiet=True)

        self.assertEqual(len(responses.calls), 1)

    @responses.activate
    def test_one_poisoned_row_does_not_stop_the_sweep(self):
        from django.core.management import call_command

        account = make_account(plan=Plan.PRO)
        make_record(account=account, recipient="First")
        make_record(account=account, recipient="Second")

        responses.add(responses.POST, SERVICE_URL, body=requests.ConnectionError("x"))
        responses.add(
            responses.POST, SERVICE_URL, json={"status": "DELIVERED"}, status=200
        )

        call_command("sweep_example_jobs", quiet=True)

        self.assertEqual(len(responses.calls), 2)


class CredentialTests(TestCase):
    """The configured-key path.

    Every other test in this file runs with PROVIDER_CREDENTIAL_ENCRYPTION_KEY
    unset, which short-circuits to a mock credential. That gap let a reference
    to a field the model did not have reach a running stack: the suite was
    green and the first real request raised AttributeError. These tests run the
    branch that actually executes in production.
    """

    # A valid Fernet key. Test-only, and it decrypts nothing real.
    KEY = "4Q4Vv2wJ0Xk6yBqz1n8sQmZ3rT7uW9xY0aB2cD4eF5g="

    def setUp(self):
        self.account = make_account(plan=Plan.PRO)
        self.record = make_record(account=self.account)

    @responses.activate
    def test_a_stored_credential_is_decrypted_and_sent(self):
        from core.crypto import encrypt_provider_credential

        with self.settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY=self.KEY):
            self.account.provider_credential_encrypted = encrypt_provider_credential("live-secret")
            self.account.save(update_fields=["provider_credential_encrypted"])

            responses.add(
                responses.POST, SERVICE_URL,
                json={"status": "DELIVERED", "reference": str(self.record.id)}, status=200,
            )

            result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.DELIVERED)
        self.assertEqual(
            responses.calls[0].request.headers["X-Provider-Credential"], "live-secret"
        )

    def test_an_account_with_no_credential_says_so(self):
        # A distinct code from DECRYPTION_ERROR: one means "set this up", the
        # other means "the key is wrong", and they need different fixes.
        with self.settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY=self.KEY):
            result = deliver_example_record(self.record)

        self.assertEqual(result.status, JobStatus.ERROR)
        self.assertEqual(result.error_code, "CREDENTIAL_UNAVAILABLE")

    def test_a_credential_encrypted_with_another_key_is_a_decryption_error(self):
        from core.crypto import encrypt_provider_credential

        with self.settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY=self.KEY):
            self.account.provider_credential_encrypted = encrypt_provider_credential("live-secret")
            self.account.save(update_fields=["provider_credential_encrypted"])

        with self.settings(
            PROVIDER_CREDENTIAL_ENCRYPTION_KEY="0123456789abcdef0123456789abcdef0123456789A="
        ):
            result = deliver_example_record(self.record)

        self.assertEqual(result.error_code, "DECRYPTION_ERROR")

    def test_the_decryption_error_never_repeats_the_ciphertext(self):
        from core.crypto import encrypt_provider_credential

        with self.settings(PROVIDER_CREDENTIAL_ENCRYPTION_KEY=self.KEY):
            self.account.provider_credential_encrypted = encrypt_provider_credential("live-secret")
            self.account.save(update_fields=["provider_credential_encrypted"])
            ciphertext = self.account.provider_credential_encrypted

        with self.settings(
            PROVIDER_CREDENTIAL_ENCRYPTION_KEY="0123456789abcdef0123456789abcdef0123456789A="
        ):
            result = deliver_example_record(self.record)

        self.assertNotIn(ciphertext, result.error_message)
        self.assertNotIn("live-secret", result.error_message)


class SerializerLeakTests(TestCase):
    """C-3 at the serialization boundary."""

    def test_the_stored_credential_is_not_in_any_api_response(self):
        from rest_framework.test import APIClient

        from common.factories import make_user
        from users.permissions import UserRole

        account = make_account(plan=Plan.PRO)
        account.provider_credential_encrypted = "ciphertext-that-must-not-escape"
        account.save(update_fields=["provider_credential_encrypted"])
        make_record(account=account)

        client = APIClient()
        client.force_authenticate(make_user(account=account, role=UserRole.OWNER))

        body = client.get("/api/example/records/").content.decode()

        self.assertNotIn("ciphertext-that-must-not-escape", body)
        self.assertNotIn("provider_credential", body)
