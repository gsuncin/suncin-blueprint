#!/usr/bin/env bash
# The exit gate (CONSTITUTION C-8). Runs everything and stops at the first red.
#
# Show the output. A summary line asserting success is not evidence; the
# printed result is.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Point at a SCRATCH database. DATABASES["default"]["TEST"] is a MIRROR, so
# Django uses DB_NAME directly rather than creating a throwaway — pointing this
# at your dev data will destroy it.
: "${DB_NAME:=acme_scratch}"
: "${DB_USER:=acme}"
: "${DB_PASSWORD:=acme}"
: "${DB_HOST:=127.0.0.1}"
# 5433 is the scratch database from docker-compose.test.yml (`make test-db`),
# deliberately not 5432, so it cannot collide with a Postgres you already run
# — or, worse, with your own development data.
: "${DB_PORT:=5433}"

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

# run <name> <working dir> <command...>
run() {
    local name="$1" dir="$2"; shift 2
    section "$name"
    if ( cd "$ROOT/$dir" && "$@" ); then
        return 0
    fi
    printf '\n\033[31mFAILED: %s\033[0m\n' "$name"
    printf 'Stopping here. A later suite failing on top of this one tells you nothing.\n'
    printf 'Blocked is not done: report this output rather than working around it.\n'
    exit 1
}

django() {
    env DEBUG=True DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" \
        DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" CELERY_TASK_ALWAYS_EAGER=True \
        .venv/bin/python manage.py "$@"
}
export -f django
export DB_NAME DB_USER DB_PASSWORD DB_HOST DB_PORT

section "environment"
printf '  DB_NAME=%s  (must be a SCRATCH database, never your dev data)\n' "$DB_NAME"
printf '  DB_HOST=%s:%s\n' "$DB_HOST" "$DB_PORT"

run "svc-example (pytest)"   acme-svc-example  .venv/bin/pytest -q
run "gateway auth (pytest)"  acme-gateway/auth .venv/bin/pytest -q

run "bff migrations"      acme-bff bash -c 'django migrate --noinput'
# The DRF throttle counters live in a database cache table, and the auth
# tests exercise throttled endpoints. Without this a FRESH scratch database
# fails with 'relation "cache_table" does not exist' — which passes on any
# machine where someone once ran this by hand, and fails in CI.
run "bff cache table"     acme-bff bash -c 'django createcachetable'
run "bff migration drift" acme-bff bash -c 'django makemigrations --check --dry-run'
run "bff (django)"        acme-bff bash -c 'django test'

run "web lint"               acme-web npm run lint
run "web build (tsc + vite)" acme-web npm run build
run "web unit (vitest)"      acme-web npm run test:unit
run "web e2e (playwright)"   acme-web npm run test:e2e

run "terraform fmt"           . terraform fmt -check -recursive acme-tf
# init first: a fresh clone has no .terraform, and `test` does not
# initialise for you — it fails with a message about the module cache that
# reads like a broken configuration.
run "terraform init"          . terraform -chdir=acme-tf/tests/render init -backend=false -input=false
run "terraform render tests"  . terraform -chdir=acme-tf/tests/render test

printf '\n\033[32mAll suites green.\033[0m\n'
