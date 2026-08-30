#!/usr/bin/env bash
# Read-only. Does not stop, start, pull or recreate anything.
#
# Exists so that "what is wrong with production?" can be answered from the
# Actions tab, by someone who is not on the tailnet and does not have the SSH
# key on the laptop they happen to be holding.
set -uo pipefail

PROJECT="${PROJECT:-acme}"
cd "/opt/${PROJECT}" || exit 1

section() { printf '\n===== %s =====\n' "$1"; }

section "deploy status"
sudo cat "/opt/${PROJECT}/deploy-status" 2>/dev/null || echo "(no deploy has recorded a status)"

section "containers"
sudo docker compose ps

section "images actually running"
for service in traefik auth web bff worker svc-example postgres rabbitmq; do
    printf '%-14s %s\n' "$service" \
      "$(sudo docker inspect -f '{{.Config.Image}} started={{.State.StartedAt}}' \
         "${PROJECT}-${service}" 2>/dev/null || echo '(not running)')"
done

section "recent logs"
for service in traefik bff web auth; do
    printf '\n--- %s ---\n' "$service"
    sudo docker compose logs --tail 40 "$service" 2>&1
done

section "health from inside each container"
sudo docker compose exec -T bff curl -sS -o /dev/null -w 'bff  /api/health -> %{http_code}\n' \
    http://127.0.0.1:8000/api/health < /dev/null
sudo docker compose exec -T web wget -qO- http://127.0.0.1:8080/healthz < /dev/null \
    && echo "web  /healthz -> ok"

section "does the gateway still resolve its upstreams?"
# The failure this catches: containers were recreated, got new IPs, and Traefik
# is holding the old ones — every request 502s with "no available server".
for service in bff web auth; do
    actual="$(sudo docker inspect -f \
        '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \
        "${PROJECT}-${service}" 2>/dev/null)"
    seen="$(sudo docker compose exec -T traefik getent hosts "$service" 2>/dev/null | awk '{print $1}')"
    printf '%-6s actual=[%s] traefik-resolves=[%s]\n' "$service" "$actual" "$seen"
done

section "C-12: published ports"
sudo docker compose ps --format '{{.Service}} {{.Publishers}}'

section "TLS"
sudo ls -la "/opt/${PROJECT}/acme/acme.json" 2>/dev/null
sudo docker compose logs traefik 2>&1 | grep -iE 'acme|certificate' | tail -10

section "disk and memory"
df -h / /mnt/data 2>/dev/null
free -m

section "recent bans"
sudo fail2ban-client status 2>/dev/null || echo "(fail2ban not reporting)"
