from unittest.mock import Mock

from django.test import TestCase

from audit.models import ProviderCall
from audit.recorder import AuditContext, record_provider_call
from audit.redaction import redact_payload, redact_text


class RedactionTests(TestCase):
    def test_sensitive_keys_are_replaced(self):
        redacted = redact_payload({"api_key": "abc123", "recipient": "Ada"})

        self.assertEqual(redacted["api_key"], "[REDACTED]")
        self.assertEqual(redacted["recipient"], "Ada")

    def test_redaction_reaches_nested_structures(self):
        redacted = redact_payload({"outer": [{"token": "abc123"}]})

        self.assertEqual(redacted["outer"][0]["token"], "[REDACTED]")

    def test_a_bearer_token_in_free_text_is_caught(self):
        # No key-based rule can see this one; providers echo credentials into
        # error strings and those strings end up in a column.
        self.assertNotIn("abc123", redact_text("failed: Bearer abc123 rejected"))

    def test_ordinary_text_survives(self):
        self.assertEqual(redact_text("recipient is required"), "recipient is required")


class RecorderTests(TestCase):
    def _response(self, status_code=200, payload=None):
        response = Mock()
        response.status_code = status_code
        response.ok = status_code < 400
        response.json.return_value = payload or {"status": "DELIVERED"}
        response.text = ""
        return response

    def test_a_successful_call_is_recorded(self):
        record_provider_call(
            AuditContext(service="svc", operation="op"),
            method="post", path="/internal/greetings",
            request_payload={"recipient": "Ada"},
            outcome=self._response(), started=0.0,
        )

        call = ProviderCall.objects.get()
        self.assertTrue(call.succeeded)
        self.assertEqual(call.method, "POST")
        self.assertEqual(call.request_payload, {"recipient": "Ada"})

    def test_the_payload_is_redacted_before_the_insert(self):
        # Before, not after: a cleanup pass that fails leaves the secret in the
        # table and in every backup taken meanwhile.
        record_provider_call(
            AuditContext(service="svc", operation="op"),
            method="post", path="/x",
            request_payload={"credential": "hunter2"},
            outcome=self._response(), started=0.0,
        )

        self.assertEqual(ProviderCall.objects.get().request_payload["credential"], "[REDACTED]")

    def test_an_unreachable_service_is_recorded_with_no_status(self):
        import requests

        record_provider_call(
            AuditContext(service="svc", operation="op"),
            method="post", path="/x", request_payload=None,
            outcome=requests.ConnectionError("connection refused"), started=0.0,
        )

        call = ProviderCall.objects.get()
        self.assertFalse(call.succeeded)
        self.assertIsNone(call.status_code)

    def test_passing_none_records_nothing(self):
        record_provider_call(
            None, method="post", path="/x", request_payload=None,
            outcome=self._response(), started=0.0,
        )

        self.assertEqual(ProviderCall.objects.count(), 0)

    def test_a_failure_to_record_never_reaches_the_caller(self):
        # An audit table that is full, locked or mid-migration must not take
        # down the operation it is observing.
        broken = Mock()
        broken.status_code = 200
        broken.ok = True
        broken.json.side_effect = RuntimeError("boom")
        broken.text = property(lambda self: (_ for _ in ()).throw(RuntimeError("boom")))

        record_provider_call(
            AuditContext(service="svc", operation="op"),
            method="post", path="/x", request_payload={"a": 1},
            outcome=broken, started=0.0,
        )
        # No exception. Whether a row landed is not the point.


class PruneTests(TestCase):
    def test_payloads_go_before_rows(self):
        from datetime import timedelta

        from django.core.management import call_command
        from django.utils import timezone

        call = ProviderCall.objects.create(
            service="svc", operation="op", direction="OUTBOUND",
            method="POST", path="/x", request_payload={"a": 1}, succeeded=True,
        )
        ProviderCall.objects.filter(pk=call.pk).update(
            created_at=timezone.now() - timedelta(days=60)
        )

        call_command("prune_audit_payloads", quiet=True)

        call.refresh_from_db()
        self.assertIsNone(call.request_payload)
        self.assertIsNotNone(call.payloads_pruned_at)
