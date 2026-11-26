#!/usr/bin/env bash
# Streamed to the box over SSH by deploy-prod.yml and executed there.
#
#   ssh host env IMAGE_TAG=... bash -s < .github/scripts/deploy-remote.sh
#
# It also answers one question without touching a box, for CI:
#
#   .github/scripts/deploy-remote.sh --print-services <compose file>
#
# THE STDIN TRAP, which has cost a full afternoon and produced a silent
# half-deploy that exited 0:
#
#   Because this runs as `bash -s < script`, bash is reading the REST OF THIS
#   FILE from stdin as it goes. `docker compose run` attaches the calling
#   process's stdin to the container by default — and `-T` does NOT stop that,
#   it only disables pty allocation. So the container competes with bash for
#   the same pipe, eats the remainder of the script, and bash hits EOF and
#   exits 0 having done half the work.
#
#   Every command below that could touch stdin therefore ends in `< /dev/null`.
set -Eeuo pipefail

# --- What this release is responsible for, derived once -----------------------
#
# THIS USED TO BE THE LITERAL LIST `bff web auth svc-example`, WRITTEN OUT FOUR
# TIMES: for the rollback digest capture, the recreate, the health wait and the
# rollback recreate. Add a microservice and no copy of the list learns about it,
# so a deploy starts part of the stack and reports success — silently, because a
# loop over a list that does not mention a service cannot fail on it.
#
# So the subjects are derived, in one place, and an empty derivation is a
# failure rather than four loops that quietly run no iterations.
#
# The rule that makes one list correct for all four uses: a service this deploy
# RE-TAGS is a service it must also pull, recreate and wait for. So the subjects
# are exactly the services whose `image:` line the pinning sed below rewrites —
# and both read the same $REGISTRY_HOST, so they cannot drift apart. Everything
# else in the stack (traefik, postgres, rabbitmq, minio) comes from a public
# registry at a version Terraform pins, and a release does not touch it.
REGISTRY_HOST="${REGISTRY_HOST:-ghcr.io}"
# The same value as a sed pattern. Unescaped, the `.` in `ghcr.io` is a
# wildcard — harmless today and not something to leave for a registry whose
# name has a hyphen or a port in it.
REGISTRY_HOST_RE="${REGISTRY_HOST//./\\.}"

release_services() {
    # <compose file> -> one service name per line.
    #
    # awk, not `docker compose config`: this same function runs in CI (see
    # --print-services below), where there is no docker daemon and none of the
    # env files the compose file references exist, which is enough to make
    # `docker compose config` refuse to parse it.
    awk -v host="$REGISTRY_HOST" '
        /^[[:space:]]*#/ { next }
        /^services:[[:space:]]*$/ { in_services = 1; next }
        # `volumes:` and `networks:` at column 0 end the services block.
        /^[^[:space:]]/ { in_services = 0 }
        !in_services { next }
        # Only the two-space-indented keys are service names. `image:` and
        # `networks:` inside a service are indented further.
        /^  [A-Za-z0-9._-]+:[[:space:]]*$/ { service = $1; sub(/:$/, "", service); next }
        # index(), not a regex: the host is data, and `ghcr.io` as a pattern
        # also matches `ghcrxio`.
        # A ref carrying `@` is pinned by digest: it is not built per release,
        # nothing re-tags it, so it is never a release service (graav-app
        # R-2026-10-16-0c4918).
        service != "" && $1 == "image:" && index($2, host "/") == 1 && index($2, "@") == 0 { print service }
    ' "$1"
}

# `--print-services <compose file>` runs that derivation and NOTHING else — no
# docker, no sudo, no box, no side effect. It exists so
# .github/scripts/check-deploy-contract.sh can run the deploy's own code in CI
# against the rendered production compose file, rather than grading a second
# copy of the parser that could agree with the same bug.
#
# It has to come before IMAGE_TAG is required and before the logging redirect
# below, both of which need a box.
if [ "${1:-}" = "--print-services" ]; then
    compose="${2:?--print-services needs the path to a compose file}"
    services="$(release_services "$compose")"
    if [ -z "$services" ]; then
        echo "no service in ${compose} takes an image from ${REGISTRY_HOST}" >&2
        exit 1
    fi
    printf '%s\n' "$services"
    exit 0
fi

PROJECT="${PROJECT:-acme}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required; deploy an immutable tag, never latest}"
INSTALL_DIR="/opt/${PROJECT}"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
LOG="/var/log/${PROJECT}-deploy.log"
STATUS="${INSTALL_DIR}/deploy-status"

# Dual sink: the file survives, and the journal gives an operator one place to
# look that is not this file.
exec > >(sudo tee -a "$LOG" | logger -t "${PROJECT}-deploy" -s 2>/dev/console) 2>&1

# A machine-readable breadcrumb, so "did the last deploy work?" does not
# require reading a log.
trap 'rc=$?; echo "$(date -Is) deploy FAILED rc=$rc line=$LINENO tag=$IMAGE_TAG" \
      | sudo tee "$STATUS"; exit $rc' ERR

echo "=== $(date -Is) deploying ${IMAGE_TAG} ==="

# The Docker tag grammar, checked here as well as in deploy-prod.yml's preflight:
# IMAGE_TAG reaches this shell through `ssh ... env IMAGE_TAG=...` and goes into
# a sed expression below.
if ! [[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "refusing '${IMAGE_TAG}': not a valid image tag" >&2
    exit 1
fi

# Build-triggered runs pass SKIP_IF_ALREADY_DEPLOYED=1: two builds of the same
# commit both trigger deploy-prod, and the second must not redeploy what the
# first already shipped. The box's own status file is the record; a dispatch
# (a deliberate redeploy) passes 0.
if [ "${SKIP_IF_ALREADY_DEPLOYED:-0}" = 1 ] \
   && sudo grep -qE " deploy succeeded tag=${IMAGE_TAG}\$" "$STATUS" 2>/dev/null; then
    echo "--- ${IMAGE_TAG} is already deployed and healthy here; nothing to do ---"
    exit 0
fi

cd "$INSTALL_DIR"

# The one list, for all four uses below. Fail closed: an empty derivation means
# every loop that follows runs zero iterations and reports success.
mapfile -t SERVICES < <(release_services "$COMPOSE_FILE")
if [ "${#SERVICES[@]}" -eq 0 ]; then
    echo "no service in ${COMPOSE_FILE} takes an image from ${REGISTRY_HOST};" >&2
    echo "refusing to deploy nothing and call it a success" >&2
    exit 1
fi
echo "--- this release covers: ${SERVICES[*]} ---"

if [ "$IMAGE_TAG" = "latest" ]; then
    # A box running `latest` cannot tell you what it is running, and rollback
    # becomes guesswork about what `latest` pointed at yesterday.
    echo "refusing to deploy 'latest'; pass an immutable tag" >&2
    exit 1
fi

echo "--- registry login ---"
echo "${REGISTRY_TOKEN}" | sudo docker login ghcr.io -u "${REGISTRY_USERNAME}" --password-stdin

# --- Record what is running now, so a failed deploy can be undone -------------
# The rollback is the compose file as it stands now: the tags the running
# containers were created from. Restoring a whole file cannot miss a service
# whose name differs from its image (`worker` runs the bff image), and the
# images are already on the box because the containers are running on them.
# The refs are logged for whoever reads the output.
echo "--- recording what runs now, for rollback ---"
ROLLBACK_FILE="${INSTALL_DIR}/rollback-images"
PREVIOUS="${INSTALL_DIR}/docker-compose.previous.yml"
sudo rm -f "$ROLLBACK_FILE"
for service in "${SERVICES[@]}"; do
    ref="$(sudo docker inspect --format '{{.Config.Image}}' \
           "${PROJECT}-${service}" 2>/dev/null || echo "")"
    [ -n "$ref" ] && echo "${service}=${ref}" | sudo tee -a "$ROLLBACK_FILE" > /dev/null
done
sudo cat "$ROLLBACK_FILE" 2>/dev/null || echo "(nothing running yet)"
sudo cp "$COMPOSE_FILE" "$PREVIOUS"

# --- Pull first, then swap -----------------------------------------------------
# The new tag goes into a staged copy, and every image is pulled from THAT copy
# before the live file changes. A missing image fails here with production
# untouched (graav-app R-2026-10-16-4ed9c2). The sed skips digest-pinned refs:
# `@` is excluded from both classes and the match is anchored to the line end.
NEXT="${INSTALL_DIR}/docker-compose.next.yml"
echo "--- staging ${NEXT} at ${IMAGE_TAG} ---"
sudo cp "$COMPOSE_FILE" "$NEXT"
sudo sed -i -E "s#^([[:space:]]*image: ${REGISTRY_HOST_RE}/[^:@[:space:]]+):[^@[:space:]]+[[:space:]]*\$#\1:${IMAGE_TAG}#" "$NEXT"
grep -n "image: ${REGISTRY_HOST}" "$NEXT"

echo "--- pulling ---"
sudo docker compose -f "$NEXT" pull < /dev/null

echo "--- every image is here; swapping the compose file ---"
sudo mv "$NEXT" "$COMPOSE_FILE"

# --- Migrate BEFORE swapping containers ---------------------------------------
# The old backend is still serving while this runs, and migrations are additive
# and backward-compatible by C-9, so the old code keeps working against the new
# schema for the seconds between here and the swap.
#
# Run once, here, rather than in an entrypoint: N containers starting together
# would race the migration lock.
echo "--- migrations ---"
sudo docker compose run --rm -T bff python manage.py migrate --noinput < /dev/null

echo "--- recreating application containers ---"
# `worker` is in SERVICES on its own merit: the production template gives it its
# own `image: ${image_bff}` line, so the derivation finds it. That is the point
# of deriving from the image lines rather than from a role — a service the
# release re-tags is a service the release restarts, with no list to maintain.
sudo docker compose up -d --no-deps --force-recreate "${SERVICES[@]}" < /dev/null

# --- Wait for health, THEN reload the proxy -----------------------------------
# The containers just got new IPs. Traefik resolved the old ones and holds
# them, so until it re-resolves every request 502s with "no available server".
# The service healthCheck in traefik/dynamic/routers.yml is what re-resolves —
# which is why those blocks are not decoration.
echo "--- waiting for health ---"
deadline=$((SECONDS + 120))
while [ "$SECONDS" -lt "$deadline" ]; do
    unhealthy=""
    for service in "${SERVICES[@]}"; do
        state="$(sudo docker inspect -f '{{.State.Health.Status}}' \
                 "${PROJECT}-${service}" 2>/dev/null || echo unknown)"
        [ "$state" = "healthy" ] || unhealthy="${unhealthy} ${service}:${state}"
    done
    [ -z "$unhealthy" ] && break
    echo "  waiting:${unhealthy}"
    sleep 5
done

if [ -n "$unhealthy" ]; then
    echo "!!! containers did not become healthy:${unhealthy}"
    echo "--- rolling back ---"
    if [ -s "$ROLLBACK_FILE" ]; then
        while IFS='=' read -r service ref; do
            echo "  restoring ${service} -> ${ref}"
        done < "$ROLLBACK_FILE"
        sudo cp "$PREVIOUS" "$COMPOSE_FILE"
        sudo docker compose up -d --no-deps --force-recreate "${SERVICES[@]}" < /dev/null
        echo "$(date -Is) deploy ROLLED BACK from ${IMAGE_TAG}" | sudo tee "$STATUS"
    else
        echo "no previous digests recorded; cannot roll back automatically"
        echo "$(date -Is) deploy FAILED, no rollback available, tag=${IMAGE_TAG}" | sudo tee "$STATUS"
    fi
    exit 1
fi

echo "--- internal health check ---"
sudo docker compose exec -T bff curl -fsS http://127.0.0.1:8000/api/health < /dev/null
echo

echo "--- pruning old images ---"
sudo docker image prune -f < /dev/null

sudo docker compose ps

echo "$(date -Is) deploy succeeded tag=${IMAGE_TAG}" | sudo tee "$STATUS"
echo "=== done ==="
