#!/usr/bin/env bash
# Assert C-12: the gateway is the only ingress.
#
# This is the check that keeps the network topology honest. It runs in CI, and
# it is meant to fail loudly the day someone adds `ports:` to a service because
# it was convenient during debugging and then forgot.
#
# Requires the stack to be up: docker compose up -d
set -uo pipefail

cd "$(dirname "$0")/.."

fail=0
pass() { printf '  ok    %s\n' "$1"; }
fault() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "C-12 — the gateway is the only ingress"
echo

# --- 1. Exactly one service publishes a host port --------------------------
echo "1. Published ports"

# Parsed from JSON, not from a Go template: `--format '{{.Publishers}}'`
# renders the struct without field names ("{ 8000 0 tcp}"), so there is nothing
# reliable to match on and a check written against it silently passes.
published="$(docker compose ps --format json 2>/dev/null | python3 -c "
import json, sys

services = set()
raw = sys.stdin.read().strip()
if raw:
    # Compose emits a JSON array on some versions and NDJSON on others.
    rows = json.loads(raw) if raw.lstrip().startswith('[') else [
        json.loads(line) for line in raw.splitlines() if line.strip()
    ]
    for row in rows:
        if any(p.get('PublishedPort') for p in (row.get('Publishers') or [])):
            services.add(row['Service'])

print('\n'.join(sorted(services)))
")"

if [ "$published" = "traefik" ]; then
    pass "only traefik publishes a port"
elif [ -z "$published" ]; then
    fault "no service publishes a port — is the stack up?"
else
    fault "these publish host ports: $(echo "$published" | paste -sd', ' -)"
fi

# Belt and braces: the compose file itself must declare exactly one `ports:`,
# so this fails in CI where nothing is running.
declared="$(docker compose config --format json 2>/dev/null \
            | python3 -c "
import json, sys
config = json.load(sys.stdin)
for name, service in sorted(config.get('services', {}).items()):
    if service.get('ports'):
        print(name)
")"
if [ "$declared" = "traefik" ]; then
    pass "compose declares ports: on traefik only"
else
    fault "compose declares ports: on [$(echo "$declared" | paste -sd', ' -)]"
fi

# --- 2. The data network has no route in or out ----------------------------
echo
echo "2. Data network isolation"
network="$(docker compose ps --format '{{.Project}}' 2>/dev/null | head -1)_data"
internal="$(docker network inspect "$network" -f '{{.Internal}}' 2>/dev/null || echo missing)"

if [ "$internal" = "true" ]; then
    pass "$network is internal: true"
else
    fault "$network is not internal (got: $internal)"
fi

# --- 3. The microservice is not reachable from outside ---------------------
echo
echo "3. Microservice reachability"
if curl -fsS --max-time 3 http://localhost:8000/health >/dev/null 2>&1; then
    fault "svc-example answered on the host at :8000"
else
    pass "svc-example does not answer on the host"
fi

if docker compose exec -T bff \
     curl -fsS --max-time 5 http://svc-example:8000/health >/dev/null 2>&1; then
    pass "svc-example answers the bff by container name"
else
    fault "svc-example is unreachable from the bff — the stack is broken, not secure"
fi

# --- 4. No Traefik router exposes the microservice -------------------------
echo
echo "4. Gateway routing"
if grep -rqE '^\s*-?\s*url:\s*"?http://svc-example' acme-gateway/traefik/dynamic/ 2>/dev/null; then
    fault "a Traefik service points at svc-example"
else
    pass "no Traefik route reaches svc-example"
fi

# --- 5. The edge proxy has no docker socket --------------------------------
echo
echo "5. Edge blast radius"
if docker compose config 2>/dev/null | grep -q 'docker.sock'; then
    fault "something mounts /var/run/docker.sock"
else
    pass "no container mounts the docker socket"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "PASS — isolation holds."
else
    echo "FAIL — see above. Widening ingress is a spec change, not a fix."
fi
exit "$fail"
