"""POST /api/public/csp-report/ — where browsers send CSP violation reports.

The gateway sends `Content-Security-Policy-Report-Only` with the same policy it
enforces plus `report-uri` here, so a script the policy blocks is visible in the
log instead of only as a feature that quietly stopped working (ported from
gestapro-monorepo R-302).

Anyone can post here, so it is narrow by construction:
- POST only, the two report content types only, at most 4 KB;
- its own throttle scope, on top of the gateway's per-IP ratelimit-public;
- the log line carries the directive, the blocked origin, and the document's
  origin and FIRST path segment. A report repeats the page URL, and a page can
  carry a token in its path (`/reset/<uid>/<token>`), so nothing past the first
  segment, and no query string, is ever written (C-3).
"""

import json
import logging
from urllib.parse import urlsplit

from django.http import HttpResponse
from rest_framework.decorators import api_view, authentication_classes, permission_classes, throttle_classes
from rest_framework.throttling import SimpleRateThrottle

logger = logging.getLogger("csp")

MAX_BYTES = 4096
CONTENT_TYPES = ("application/csp-report", "application/reports+json", "application/json")


class CspReportThrottle(SimpleRateThrottle):
    """Per client address (DRF's NUM_PROXIES reads it from X-Forwarded-For)."""

    scope = "csp_report"

    def get_cache_key(self, request, view):
        return self.cache_format % {"scope": self.scope, "ident": self.get_ident(request)}


def _origin(url: str) -> str:
    parts = urlsplit(url or "")
    if parts.scheme in ("http", "https") and parts.netloc:
        return f"{parts.scheme}://{parts.netloc}"
    # `inline`, `eval`, `data`, `self`: keywords, not URLs, and safe to keep.
    return (url or "")[:32].split(":")[0]


def _page(url: str) -> str:
    parts = urlsplit(url or "")
    first = parts.path.strip("/").split("/")[0] if parts.path.strip("/") else ""
    return f"{_origin(url)}/{first}/" if first else f"{_origin(url)}/"


def _violations(payload) -> list[dict]:
    """Both report shapes: report-uri's {"csp-report": {...}} and the Reporting
    API's [{"type": "csp-violation", "body": {...}}]."""
    if isinstance(payload, dict) and isinstance(payload.get("csp-report"), dict):
        r = payload["csp-report"]
        return [{
            "directive": r.get("effective-directive") or r.get("violated-directive") or "",
            "blocked": r.get("blocked-uri") or "",
            "document": r.get("document-uri") or "",
        }]
    if isinstance(payload, list):
        found = []
        for item in payload[:10]:
            body = item.get("body") if isinstance(item, dict) else None
            if isinstance(body, dict):
                found.append({
                    "directive": body.get("effectiveDirective") or "",
                    "blocked": body.get("blockedURL") or "",
                    "document": body.get("documentURL") or "",
                })
        return found
    return []


@api_view(["POST"])
@authentication_classes([])
@permission_classes([])
@throttle_classes([CspReportThrottle])
def csp_report(request) -> HttpResponse:
    content_type = (request.content_type or "").split(";")[0].strip().lower()
    if content_type not in CONTENT_TYPES:
        return HttpResponse(status=415)
    declared = request.META.get("CONTENT_LENGTH") or "0"
    if (declared.isdigit() and int(declared) > MAX_BYTES) or len(request.body) > MAX_BYTES:
        return HttpResponse(status=413)
    try:
        payload = json.loads(request.body or b"null")
    except (ValueError, UnicodeDecodeError):
        return HttpResponse(status=400)

    for violation in _violations(payload):
        logger.warning(
            "csp violation directive=%s blocked=%s page=%s",
            str(violation["directive"])[:64],
            _origin(str(violation["blocked"])),
            _page(str(violation["document"])),
        )
    return HttpResponse(status=204)
