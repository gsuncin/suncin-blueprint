"""Infrastructure-level tests: the things every other test assumes."""

import json

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from core.crypto import EncryptionError, make_fernet_helpers
from core.logging import SCHEMA
from core.sentry import scrub_event


class HealthTests(TestCase):
    def test_health_is_open_and_reports_ok(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")


class JwksTests(TestCase):
    def test_jwks_is_public_and_well_formed(self):
        # The gateway must be able to fetch this before it can authenticate
        # anything, so it cannot itself require authentication.
        response = APIClient().get(reverse("jwks"))

        self.assertEqual(response.status_code, 200)
        key = response.json()["keys"][0]
        self.assertEqual(key["kty"], "RSA")
        self.assertEqual(key["alg"], "RS256")
        self.assertTrue(key["kid"])

    def test_jwks_never_contains_the_private_key(self):
        body = json.dumps(APIClient().get(reverse("jwks")).json())

        self.assertNotIn("PRIVATE", body)
        self.assertNotIn("d", json.loads(body)["keys"][0])

    def test_the_kid_is_stable_across_requests(self):
        # A kid that changed per request would make caching impossible and
        # force the verifier to refetch on every call.
        first = APIClient().get(reverse("jwks")).json()["keys"][0]["kid"]
        second = APIClient().get(reverse("jwks")).json()["keys"][0]["kid"]

        self.assertEqual(first, second)


class CryptoTests(TestCase):
    def test_round_trips(self):
        with self.settings(TEST_KEY="4Q4Vv2wJ0Xk6yBqz1n8sQmZ3rT7uW9xY0aB2cD4eF5g="):
            encrypt, decrypt = make_fernet_helpers("TEST_KEY")
            self.assertEqual(decrypt(encrypt("hunter2")), "hunter2")

    def test_a_missing_key_names_the_setting_not_the_value(self):
        encrypt, _ = make_fernet_helpers("ABSENT_KEY")

        with self.assertRaises(EncryptionError) as ctx:
            encrypt("secret-value")

        self.assertIn("ABSENT_KEY", str(ctx.exception))
        self.assertNotIn("secret-value", str(ctx.exception))

    def test_the_wrong_key_fails_loudly_rather_than_returning_garbage(self):
        with self.settings(KEY_A="4Q4Vv2wJ0Xk6yBqz1n8sQmZ3rT7uW9xY0aB2cD4eF5g="):
            encrypt, _ = make_fernet_helpers("KEY_A")
            ciphertext = encrypt("hunter2")

        with self.settings(KEY_B="0123456789abcdef0123456789abcdef0123456789A="):
            _, decrypt = make_fernet_helpers("KEY_B")
            with self.assertRaises(EncryptionError):
                decrypt(ciphertext)


class LoggingTests(TestCase):
    def test_the_formatter_emits_the_versioned_schema(self):
        import logging

        from core.logging import JsonFormatter

        record = logging.LogRecord(
            "test", logging.INFO, __file__, 1, "hello", None, None
        )
        payload = json.loads(JsonFormatter().format(record))

        self.assertEqual(payload["schema"], SCHEMA)
        self.assertEqual(payload["message"], "hello")


class SentryScrubbingTests(TestCase):
    def test_secrets_are_replaced_before_the_event_leaves(self):
        event = scrub_event(
            {"request": {"headers": {"Authorization": "Bearer abc", "Accept": "json"}}}, {}
        )

        headers = event["request"]["headers"]
        self.assertEqual(headers["Authorization"], "[REDACTED]")
        self.assertEqual(headers["Accept"], "json")

    def test_only_the_ids_survive_on_the_user(self):
        # An email in a breadcrumb is a personal-data export to a third party,
        # and it is never the field that helps you debug.
        event = scrub_event(
            {"user": {"id": "1", "account_id": "2", "email": "ada@acme.test"}}, {}
        )

        self.assertEqual(event["user"], {"id": "1", "account_id": "2"})


class SettingsIsolationTests(TestCase):
    """The suite must not be configured by a file in a parent directory."""

    def test_env_loading_is_pinned_to_this_project(self):
        # python-decouple's AutoConfig walks UP the tree, so the repo-root .env
        # that configures docker compose was being read by `manage.py test`.
        # Whether a test passed then depended on whether someone had run
        # `make keys` — a gitignored file, different on every machine, absent
        # in CI. core.settings.env pins the search to one path.
        from core.settings.env import BASE_DIR, _env_file

        self.assertEqual(_env_file.parent, BASE_DIR)
        self.assertEqual(_env_file.name, ".env")
