#!/usr/bin/env bash
# Makes a fresh git worktree able to run the suites, without touching the main
# checkout. Ported from graav-app. `.venv` and `node_modules` are not tracked,
# so a new worktree has neither, and three things go wrong by default when
# worktrees run side by side:
#
# - a shared scratch database: two Django suites on acme_scratch fight over one
#   schema (TEST.MIRROR writes straight into DB_NAME). Each worktree gets its
#   own DB_NAME.
# - port 3000: Playwright reuses whatever answers there, so a parallel worktree,
#   or another project's container, gets tested in place of this one. Each
#   worktree gets its own E2E_PORT (acme-web/playwright.config.ts reads it).
# - a venv's scripts carry the main checkout's path in their shebang, so a plain
#   copy still runs the main checkout's Python. They are rewritten here.
#
# Usage: ./scripts/worktree-bootstrap.sh    then: source .worktree.env
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
MAIN="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
cd "$ROOT"

if [ "$ROOT" = "$MAIN" ]; then
    echo "FAIL  this is the main checkout; run it inside a worktree" >&2
    exit 1
fi

slug="$(basename "$ROOT" | tr -c 'a-zA-Z0-9\n' '_')"
db="acme_wt_${slug}"
port=$(( 3100 + $(printf '%s' "$ROOT" | cksum | cut -d' ' -f1) % 800 ))

# In-place sed that works with both BSD (macOS) and GNU sed.
sed_in_place() { local expr="$1" file="$2"; sed "$expr" "$file" > "$file.wt" && cat "$file.wt" > "$file" && rm "$file.wt"; }

# Derived, not listed: every Python project with a venv in the main checkout.
for project in acme-bff acme-svc-* acme-gateway/auth; do
    [ -d "$MAIN/$project/.venv" ] || continue
    [ -d "$project/.venv" ] && continue
    cp -R "$MAIN/$project/.venv" "$project/.venv"
    for script in $(grep -lIs "^#!$MAIN/$project/.venv/" "$project"/.venv/bin/* || true); do
        sed_in_place "1s|^#!$MAIN/$project/.venv/|#!$ROOT/$project/.venv/|" "$script"
    done
done

[ -d acme-web/node_modules/.bin ] || npm --prefix acme-web ci --no-audit --no-fund >/dev/null

docker inspect -f '{{.State.Running}}' acme-postgres-test 2>/dev/null | grep -qx true \
    || make test-db >/dev/null
make test-db-reset SCRATCH_DB="$db" >/dev/null

cat > .worktree.env <<ENV
export DB_NAME=$db DB_USER=acme DB_PASSWORD=acme DB_HOST=127.0.0.1 DB_PORT=5433
export DEBUG=True CELERY_TASK_ALWAYS_EAGER=True
export E2E_PORT=$port
ENV
# .nvmrc pins the web's Node; use it when nvm has it installed.
node_dir="$(ls -d "$HOME/.nvm/versions/node/v$(cat acme-web/.nvmrc)"* 2>/dev/null | tail -1 || true)"
[ -z "$node_dir" ] || echo "export PATH=\"$node_dir/bin:\$PATH\"" >> .worktree.env
echo "ready: DB_NAME=$db E2E_PORT=$port (source .worktree.env)"
