#!/usr/bin/env bash
# Assert C-12: the gateway is the only ingress.
#
# This is the check that keeps the network topology honest. It runs in CI, and
# it is meant to fail loudly the day someone adds `ports:` to a service because
# it was convenient during debugging and then forgot.
#
# The internal services are DERIVED, from the `acme-svc-*` directories — the
# same source the CI matrix reads. A hand-typed list here goes on reporting
# "isolation holds" about a topology it has never looked at: the service added
# after the last edit is simply not a subject of any check. Deriving from the
# directories, not from compose, is what keeps check 1b meaningful — a service
# that exists and is not declared in compose must still be found missing.
#
# Requires the stack to be up for the runtime checks: docker compose up -d
set -uo pipefail

cd "$(dirname "$0")/.."

fail=0
pass() { printf '  ok    %s\n' "$1"; }
fault() { printf '  FAIL  %s\n' "$1"; fail=1; }

# Reachable only from the bff, by container name, on the `services` network.
INTERNAL_SERVICES=()
for dir in acme-svc-*/; do
    # A Dockerfile, not just a directory: git leaves a removed service's
    # gitignored .venv and __pycache__ behind, and that empty shell is not a
    # service.
    [ -f "${dir}Dockerfile" ] || continue
    dir="${dir%/}"
    INTERNAL_SERVICES+=("${dir#acme-}")
done
# Fail closed: every loop below over an empty list is a pass that checked nothing.
if [ "${#INTERNAL_SERVICES[@]}" -eq 0 ]; then
    echo "FAIL  no acme-svc-* directory found — refusing to report on nothing" >&2
    exit 1
fi

echo "C-12 — the gateway is the only ingress"
echo "  internal services: ${INTERNAL_SERVICES[*]}"
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

# --- 1b. Every internal service is declared, on the right network ----------
#
# A port check says nothing about a service that is not in the compose file at
# all. This is the check that catches a service being built, tested, released
# and then never wired into the stack.
echo
echo "1b. Topology declared in compose"

# Exported under a DIFFERENT name on purpose. `export INTERNAL_SERVICES=...`
# when INTERNAL_SERVICES is an array assigns to element 0 and exports nothing,
# so the python sees no variable AND the service list itself is corrupted for
# every loop below.
#
# And it must be exported at all, not prefixed: `VAR=x cmd | python3` sets VAR
# for `cmd` only, so the python at the far end of the pipe never sees it. That
# mistake raises a KeyError, prints nothing to stdout, and the emptiness then
# reads as "no faults" — a traceback reported as ok. Hence the `||` below: a
# check that cannot run is a failure, never a pass.
export EXPECTED_INTERNAL_SERVICES="${INTERNAL_SERVICES[*]}"
if ! topology="$(docker compose config --format json 2>/dev/null \
                 | python3 -c '
import json, os, sys

config = json.load(sys.stdin)
services = config.get("services", {})

expected = {name: {"services"} for name in os.environ["EXPECTED_INTERNAL_SERVICES"].split()}
# Object storage holds tenant files and has no business making, or receiving,
# a connection off the box.
expected["minio"] = {"data"}

for name, want in sorted(expected.items()):
    service = services.get(name)
    if service is None:
        print(f"{name} is not in the compose file at all")
        continue
    got = set((service.get("networks") or {}).keys())
    if got != want:
        shown = ", ".join(sorted(got)) or "no network"
        wanted = ", ".join(sorted(want))
        print(f"{name} is on [{shown}], expected [{wanted}]")
')"; then
    fault "the topology check could not run — compose config or python failed"
elif [ -z "$topology" ]; then
    pass "${INTERNAL_SERVICES[*]} on services; minio on data"
else
    while IFS= read -r line; do fault "$line"; done <<< "$topology"
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

# --- 3. The microservices are not reachable from outside -------------------
echo
echo "3. Microservice reachability"

# One probe, not one per service: they all listen on 8000 inside their own
# container, so what is being asserted is that nothing at all answers on the
# host there. Check 1 is what proves no individual service published it.
if curl -fsS --max-time 3 http://localhost:8000/health >/dev/null 2>&1; then
    fault "something answered /health on the host at :8000"
else
    pass "no service answers on the host at :8000"
fi

for svc in "${INTERNAL_SERVICES[@]}"; do
    if docker compose exec -T bff \
         curl -fsS --max-time 5 "http://${svc}:8000/health" >/dev/null 2>&1; then
        pass "${svc} answers the bff by container name"
    else
        fault "${svc} is unreachable from the bff — the stack is broken, not secure"
    fi
done

# The edge network is where a compromised container is most likely to be, so
# it is the one that must NOT be able to reach a service that trusts its
# caller. `auth` is on edge only, which makes it the honest probe.
for svc in "${INTERNAL_SERVICES[@]}"; do
    if docker compose exec -T auth \
         curl -fsS --max-time 5 "http://${svc}:8000/health" >/dev/null 2>&1; then
        fault "${svc} is reachable from the edge network — the services network is not segregated"
    else
        pass "${svc} is unreachable from the edge network"
    fi
done

# --- 3b. Object storage is reachable from the bff and nowhere else ---------
echo
echo "3b. Object storage"
if docker compose exec -T bff \
     curl -fsS --max-time 5 http://minio:9000/minio/health/live >/dev/null 2>&1; then
    pass "minio answers the bff by container name"
else
    fault "minio is unreachable from the bff — the stack is broken, not secure"
fi

if docker compose exec -T auth \
     curl -fsS --max-time 5 http://minio:9000/minio/health/live >/dev/null 2>&1; then
    fault "minio is reachable from the edge network"
else
    pass "minio is unreachable from the edge network"
fi

# --- 4. No Traefik router exposes an internal service ----------------------
echo
echo "4. Gateway routing"
for svc in "${INTERNAL_SERVICES[@]}" minio; do
    if grep -rqE "^\s*-?\s*url:\s*\"?http://${svc}[:/]" acme-gateway/traefik/dynamic/ 2>/dev/null; then
        fault "a Traefik service points at ${svc}"
    else
        pass "no Traefik route reaches ${svc}"
    fi
done

# --- 4b. No chain inherits trust by omission -------------------------------
# `forward-auth`'s authResponseHeaders is what makes the identity headers
# trustworthy on the authenticated chains: the auth service's values REPLACE
# whatever the client sent. A chain without forward-auth must therefore strip
# them explicitly — otherwise a stranger sets X-Auth-Account-Id and the BFF is
# handed it.
echo
echo "4b. Every chain authenticates or strips"
MW=acme-gateway/traefik/dynamic/middlewares.yml
DEV=acme-gateway/traefik/dynamic/routers.yml
PROD=acme-tf/modules/app-stack/templates/routers.yml.tftpl

# A check written as "find the public chain and assert it strips" is made green
# by deleting the chain. This one derives its subjects — every chain in the
# file — and fails closed when it cannot find any.
chains_total=$(grep -cE '^    [A-Za-z0-9-]+-chain:[ ]*$' "$MW" || true)
if [ "${chains_total:-0}" -eq 0 ]; then
    fault "no chains found in $MW — this check cannot run, so it fails rather than passing"
else
    unguarded=$(awk '
      # COMMENTS ARE SKIPPED, and that is load-bearing rather than tidiness: a
      # comment above a chain saying "no forward-auth, and that is the whole
      # point" accumulates into the PRECEDING chain and makes this check green
      # about a chain that has stopped stripping. A guard that reads prose is a
      # guard that can be talked out of failing.
      /^[ ]*#/ { next }
      /^    [A-Za-z0-9-]+:[ ]*$/ {
        if (cur ~ /-chain$/) verdict()
        cur = $1; sub(/:$/, "", cur); body = ""; next
      }
      { body = body " " $0 }
      END { if (cur ~ /-chain$/) verdict(); print bad }
      function verdict() {
        if (body !~ /forward-auth/ && body !~ /strip-identity-headers/) bad = bad " " cur
      }
    ' "$MW")
    if [ -n "$unguarded" ]; then
        fault "chains with neither forward-auth nor strip-identity-headers:$unguarded"
    else
        pass "all $chains_total chains either authenticate or strip client-supplied identity headers"
    fi
fi

# Every router must name a chain, not an inline middleware list: that is what
# makes the check above cover every route rather than every chain.
for f in "$DEV" "$PROD"; do
    inline=$(grep -nE '^\s+middlewares: \[' "$f" \
        | grep -vE '\[[a-z-]+-chain\]' \
        | grep -vE 'block-all' || true)
    if [ -n "$inline" ]; then
        fault "$f has routers with inline middleware lists rather than a named chain:
$inline"
    else
        pass "$(basename "$f"): every router names a chain"
    fi
done

# A router naming a chain that does not exist is a 500 at the edge, so it is a
# fault here — and it is also how the previous shape of this check was made
# green: delete the chain and there is nothing left to find.
defined_chains=$(grep -oE '^    [A-Za-z0-9-]+-chain:' "$MW" | tr -d ' :' | sort -u)
for f in "$DEV" "$PROD"; do
    missing=""
    for named in $(grep -oE 'middlewares: \[[A-Za-z0-9-]+-chain\]' "$f" \
                   | grep -oE '[A-Za-z0-9-]+-chain' | sort -u); do
        grep -qx "$named" <<<"$defined_chains" || missing="$missing $named"
    done
    if [ -n "$missing" ]; then
        fault "$(basename "$f") names chains that $MW does not define:$missing"
    else
        pass "$(basename "$f"): every chain it names is defined"
    fi
done

# The two router files are maintained by hand and the only thing keeping them
# in step is a comment. A router present in one and not the other is a route
# that behaves differently in production than anywhere it was tested.
dev_routers=$(awk '/^    [a-z-]+:$/ {gsub(/[ :]/,"",$0); print}' "$DEV" | sort)
prod_routers=$(awk '/^    [a-z-]+:$/ {gsub(/[ :]/,"",$0); print}' "$PROD" | sort)
if [ "$dev_routers" = "$prod_routers" ]; then
    pass "dev and production declare the same routers"
else
    fault "dev and production routers differ:
$(diff <(echo "$dev_routers") <(echo "$prod_routers") || true)"
fi

# --- 4c. Traefik actually LOADED this config -------------------------------
# Every check above reads the files. Traefik reads them too, and rejects the
# whole dynamic configuration on a single YAML fault — keeping the last good
# one and carrying on serving, so the stack looks healthy while the change you
# just made is not live. A duplicate key passes `terraform test`, passes every
# render assertion and passes every static check here; only the edge notices.
echo
echo "4c. The edge loaded it"
traefik_container=$(docker compose ps --format '{{.Name}}' traefik 2>/dev/null | head -1)
if [ -n "$traefik_container" ]; then
    touch acme-gateway/traefik/dynamic/*.yml
    sleep 4
    if docker logs "$traefik_container" --since 10s 2>&1 | grep -q "watcher callback"; then
        fault "traefik REJECTED the dynamic config — it is serving the last good one, not this one:
$(docker logs "$traefik_container" --since 10s 2>&1 | grep 'watcher callback' | tail -1)"
    else
        pass "traefik reloaded the dynamic config with no error"
    fi
else
    fault "the traefik container is not running; cannot confirm the edge accepts this config"
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
