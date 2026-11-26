#!/usr/bin/env bash
# The report-only CSP must be the enforced one plus its report-uri, and nothing
# else. A report-only policy that drifts from the enforced one reports on a
# policy nobody runs, and is worse than none: it looks like coverage.
set -euo pipefail

cd "$(dirname "$0")/../.."
FILE=acme-gateway/traefik/dynamic/middlewares.yml

policy_of() { # header name -> its folded value, one line
  yq -r ".http.middlewares.\"security-headers\".headers.customResponseHeaders.\"$1\" // \"\"" "$FILE" \
    | tr -s '[:space:]' ' ' | sed -E 's/^ //; s/ $//'
}

enforced="$(policy_of Content-Security-Policy)"
report_only="$(policy_of Content-Security-Policy-Report-Only)"
failures=0

if [ -z "$enforced" ] || [ -z "$report_only" ]; then
  echo "FAIL: could not read both policies from $FILE"
  exit 1
fi
if [ "$report_only" = "${enforced}; report-uri /api/public/csp-report/" ]; then
  echo "ok: the report-only policy is the enforced one plus report-uri"
else
  echo "FAIL: the two policies differ:"
  echo "  enforced:    $enforced"
  echo "  report-only: $report_only"
  failures=$((failures + 1))
fi
if grep -q 'path("api/public/csp-report/"' acme-bff/core/urls.py; then
  echo "ok: the BFF serves the report-uri"
else
  echo "FAIL: acme-bff/core/urls.py does not route api/public/csp-report/"
  failures=$((failures + 1))
fi
[ "$failures" -eq 0 ] && echo "all passed" || exit 1
