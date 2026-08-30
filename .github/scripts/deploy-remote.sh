#!/usr/bin/env bash
# Streamed to the box over SSH by deploy-prod.yml and executed there.
#
#   ssh host env IMAGE_TAG=... bash -s < .github/scripts/deploy-remote.sh
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

PROJECT="${PROJECT:-acme}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG is required; deploy an immutable tag, never latest}"
INSTALL_DIR="/opt/${PROJECT}"
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

cd "$INSTALL_DIR"

if [ "$IMAGE_TAG" = "latest" ]; then
    # A box running `latest` cannot tell you what it is running, and rollback
    # becomes guesswork about what `latest` pointed at yesterday.
    echo "refusing to deploy 'latest'; pass an immutable tag" >&2
    exit 1
fi

echo "--- registry login ---"
echo "${REGISTRY_TOKEN}" | sudo docker login ghcr.io -u "${REGISTRY_USERNAME}" --password-stdin

# --- Record what is running now, so a failed deploy can be undone -------------
echo "--- capturing current image digests for rollback ---"
ROLLBACK_FILE="${INSTALL_DIR}/rollback-images"
sudo rm -f "$ROLLBACK_FILE"
for service in bff web auth svc-example; do
    digest="$(sudo docker inspect --format '{{index .RepoDigests 0}}' \
              "${PROJECT}-${service}" 2>/dev/null || echo "")"
    [ -n "$digest" ] && echo "${service}=${digest}" | sudo tee -a "$ROLLBACK_FILE" > /dev/null
done
sudo cat "$ROLLBACK_FILE" 2>/dev/null || echo "(nothing running yet)"

# --- Point the compose file at the new tag ------------------------------------
echo "--- pinning images to ${IMAGE_TAG} ---"
sudo sed -i -E "s#(image: ghcr\.io/[^:[:space:]]+):[^[:space:]]+#\1:${IMAGE_TAG}#" docker-compose.yml
grep -n 'image: ghcr.io' docker-compose.yml

echo "--- pulling ---"
sudo docker compose pull < /dev/null

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
sudo docker compose up -d --no-deps --force-recreate bff worker web auth svc-example < /dev/null

# --- Wait for health, THEN reload the proxy -----------------------------------
# The containers just got new IPs. Traefik resolved the old ones and holds
# them, so until it re-resolves every request 502s with "no available server".
# The service healthCheck in traefik/dynamic/routers.yml is what re-resolves —
# which is why those blocks are not decoration.
echo "--- waiting for health ---"
deadline=$((SECONDS + 120))
while [ "$SECONDS" -lt "$deadline" ]; do
    unhealthy=""
    for service in bff web auth svc-example; do
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
        while IFS='=' read -r service digest; do
            echo "  restoring ${service} -> ${digest}"
            sudo sed -i -E "s#(image: ghcr\.io/[^[:space:]]*${service}):[^[:space:]]+#${digest}#" \
                docker-compose.yml
        done < "$ROLLBACK_FILE"
        sudo docker compose up -d --no-deps --force-recreate bff web auth svc-example < /dev/null
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
