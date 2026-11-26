"""The CSP report endpoint: what a browser may post, and what reaches the log.

The gateway sends `Content-Security-Policy-Report-Only` with the same policy it
enforces, plus `report-uri /api/public/csp-report/`. Without it, a script the
policy blocks shows up only as a button that stopped working (gestapro-monorepo
R-302 found inline scripts of a payment provider that way).
"""

import json
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

REPORT = {
    "csp-report": {
        "document-uri": "https://app.example.com/reset/MQ/abc-secret-token?next=/x",
        "violated-directive": "script-src-elem",
        "effective-directive": "script-src-elem",
        "blocked-uri": "https://cdn.evil.test/lib.js?k=v",
        "original-policy": "default-src 'self'",
        "disposition": "report",
    }
}


class CspReportTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.url = reverse("csp-report")

    def post(self, body, content_type="application/csp-report"):
        data = body if isinstance(body, (bytes, str)) else json.dumps(body)
        return self.client.post(self.url, data=data, content_type=content_type)

    def test_route_is_under_the_anonymous_prefix(self):
        # The gateway routes /api/public/ to public-anon-chain; anywhere else
        # forwardAuth would refuse every browser report.
        self.assertEqual(self.url, "/api/public/csp-report/")

    def test_a_browser_report_is_accepted_without_credentials(self):
        response = self.post(REPORT)
        self.assertEqual(response.status_code, 204)

    def test_the_reporting_api_shape_is_accepted_too(self):
        body = [{"type": "csp-violation", "body": {
            "documentURL": "https://app.example.com/clients",
            "effectiveDirective": "img-src",
            "blockedURL": "https://img.test/x.png",
        }}]
        response = self.post(body, content_type="application/reports+json")
        self.assertEqual(response.status_code, 204)

    def test_only_post(self):
        self.assertEqual(self.client.get(self.url).status_code, 405)

    def test_other_content_types_are_refused(self):
        response = self.post(REPORT, content_type="text/plain")
        self.assertEqual(response.status_code, 415)

    def test_a_body_over_4kb_is_refused(self):
        big = dict(REPORT)
        big["csp-report"] = dict(REPORT["csp-report"], **{"script-sample": "x" * 5000})
        response = self.post(big)
        self.assertEqual(response.status_code, 413)

    def test_unreadable_json_is_a_400(self):
        response = self.post(b"{not json")
        self.assertEqual(response.status_code, 400)

    def test_the_log_carries_no_path_query_or_token(self):
        # A report repeats the page URL, and a page can carry a token in its
        # path (/reset/<uid>/<token>). Only the origin and the first path
        # segment are logged; the blocked URI loses its path and query too.
        # The suite runner disables logging (core/test_runner.py), so the
        # logger itself is observed, and each call formatted as it would be.
        with mock.patch("core.csp_report.logger") as logger:
            response = self.post(REPORT)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(logger.warning.call_count, 1)
        message, *args = logger.warning.call_args.args
        line = message % tuple(args)
        self.assertIn("script-src-elem", line)
        self.assertIn("https://cdn.evil.test", line)
        self.assertIn("/reset/", line)
        self.assertNotIn("abc-secret-token", line)
        self.assertNotIn("MQ", line)
        self.assertNotIn("next=", line)
        self.assertNotIn("lib.js", line)
        self.assertNotIn("k=v", line)

    def test_it_is_throttled_per_client(self):
        with mock.patch("core.csp_report.CspReportThrottle.THROTTLE_RATES", {"csp_report": "2/min"}):
            codes = [self.post(REPORT).status_code for _ in range(3)]
        self.assertEqual(codes, [204, 204, 429])
