#!/usr/bin/env bash
# Run exactly what CI runs, in CI's environment.
#
# `scripts/run-all-tests.sh` is most of it. Three things were missing, and all
# three have produced a green local run against a red CI run, or the reverse:
#
#   1. **CI has no secrets.** A developer's shell and a developer's `.env` are
#      the difference. A suite that reads a provider key from the
#      developer's shell passes locally and fails in CI with a configuration
#      error that reads as a defect in the change under test. Blanking the
#      environment is the only thing that catches it.
#   2. **`terraform validate`, every root module.** `run-all-tests.sh` runs
#      `fmt -check` and the render tests, which between them validate ONE
#      directory of the eight or so under `envs/`, `modules/` and `tests/`.
#      CI's `terraform-checks.yml` loops over all of them.
#   3. **`manage.py check --deploy`.** The BFF's composition root refuses to
#      start without its required settings, and that refusal is only reachable
#      with `DEBUG=False` — which no local run has. A required setting CI has
#      not been given goes green locally and red in CI in under a minute.
#
# What it deliberately does NOT do: tfsec (CI runs it in a container action,
# and a second local installation path is a thing to keep in step for no gain)
# and the four `docker-*.yml` image builds. Say so rather than implying parity
# that is not there.
#
# Needs the scratch database:  make test-db
set -uo pipefail

cd "$(dirname "$0")/.."

# --- 1. CI has no .env, and neither may this ------------------------------
#
# `core/settings/env.py` pins python-decouple to `acme-bff/.env` and nothing
# above it. If that file exists, this script cannot honestly claim to be running
# in CI's environment — `env -i` scrubs variables, not files. Refusing is the
# point: a developer-only file is exactly the mask this script exists to lift.
if [ -f acme-bff/.env ]; then
    echo "FAIL  acme-bff/.env exists. CI has no such file, and core/settings/env.py"
    echo "      reads it, so this run would not be CI's environment — it would be"
    echo "      yours with the variables hidden. Move it aside and run again:"
    echo "        mv acme-bff/.env acme-bff/.env.local-backup"
    exit 1
fi

# --- 2. The names that must be empty, derived from .env.example ------------
#
# Derived rather than listed, for the reason every other derivation in this
# repository is: a hand-typed list of secrets goes stale the first time someone
# adds one, and the stale entry is invisible because the loop still passes.
# Fails closed on an empty derivation.
#
# A `while read` rather than `mapfile`, because macOS ships bash 3.2 and every
# other script here still runs on it.
CI_PROVIDES="DEBUG SECRET_KEY DB_NAME DB_USER DB_PASSWORD DB_HOST DB_PORT CELERY_TASK_ALWAYS_EAGER"
declared_count=0
blanked_count=0
while read -r name; do
    [ -n "$name" ] || continue
    declared_count=$((declared_count + 1))
    case " $CI_PROVIDES " in *" $name "*) continue ;; esac
    blanked_count=$((blanked_count + 1))
done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' .env.example | tr -d '=' | sort -u)

if [ "$declared_count" -eq 0 ]; then
    echo "FAIL  no variable names found in .env.example — refusing to report a"
    echo "      blanked-secret run it could not verify was blanked"
    exit 1
fi

printf '\n\033[1m=== environment ===\033[0m\n'
printf '  %d names in .env.example, %d of them blanked for this run\n' \
    "$declared_count" "$blanked_count"
printf '  CI provides only: %s\n' "$CI_PROVIDES"
printf '  acme-bff/.env: absent, as in CI\n'

# `env -i` is what makes this real rather than aspirational: the child process
# starts with an empty environment and receives back only what is named here.
# PATH, HOME, LANG and TMPDIR are toolchain, not configuration — npm needs a
# cache directory, Playwright needs a browser path, and a runner has all four.
scrubbed() {
    env -i \
        PATH="$PATH" HOME="$HOME" LANG="${LANG:-C.UTF-8}" TMPDIR="${TMPDIR:-/tmp}" \
        DEBUG=True \
        SECRET_KEY=ci-only-not-a-real-key \
        DB_NAME="${DB_NAME:-acme_scratch}" DB_USER=acme DB_PASSWORD=acme \
        DB_HOST=127.0.0.1 DB_PORT=5433 \
        CELERY_TASK_ALWAYS_EAGER=True \
        "$@"
}

fail=0
step() {
    local name="$1"; shift
    printf '\n\033[1m=== %s ===\033[0m\n' "$name"
    if ! "$@"; then
        printf '\033[31mFAILED: %s\033[0m\n' "$name"
        fail=1
        return 1
    fi
}

# --- 3. Every suite, with nothing in the environment -----------------------
step "every suite, secrets blanked" scrubbed ./scripts/run-all-tests.sh || {
    echo "Stopping: a red suite under blanked secrets is the finding, and the"
    echo "checks below would only add noise to it."
    exit 1
}

# --- 4. terraform validate, every root module ------------------------------
#
# The loop and its subject list are copied from .github/workflows/
# terraform-checks.yml on purpose. `terraform test` in tests/render validates
# that one directory and reads as though it validated the configuration.
step "terraform validate, every root module" bash -c '
    set -e
    found=0
    for dir in acme-tf/envs/*/ acme-tf/modules/*/ acme-tf/tests/*/; do
        [ -d "$dir" ] || continue
        echo "--- $dir"
        terraform -chdir="$dir" init -backend=false -input=false >/dev/null
        terraform -chdir="$dir" validate
        found=$((found + 1))
    done
    [ "$found" -gt 0 ] || { echo "no root module found — that is a failure, not a pass"; exit 1; }
    echo "$found root modules validated"
'

# --- 5. check --deploy, with DEBUG off -------------------------------------
#
# The key is generated here rather than carried, exactly as bff-tests.yml does
# it and for the reason written there: `check --deploy` starts the process and
# signs nothing, so a throwaway key is the honest expression of what the step
# needs rather than a weaker version of a real one.
step "manage.py check --deploy (DEBUG off, the composition root's refusals)" \
    bash -c '
    set -e
    cd acme-bff
    key="$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null | base64 | tr -d "\n")"
    env -i PATH="$PATH" HOME="$HOME" LANG="${LANG:-C.UTF-8}" \
        DEBUG=False \
        ALLOWED_HOSTS=app.example.com \
        SECRET_KEY=ci-only-not-a-real-key \
        JWT_PRIVATE_KEY_B64="$key" \
        PROPOSAL_CODE_SECRET=check-deploy-only \
        STORAGE_ENDPOINT=http://minio.invalid:9000 \
        STORAGE_ACCESS_KEY=check-deploy-only \
        STORAGE_SECRET_KEY=check-deploy-only \
        STORAGE_BUCKET_PRIVATE=check-deploy-only \
        DB_NAME=acme_scratch DB_USER=acme DB_PASSWORD=acme \
        DB_HOST=127.0.0.1 DB_PORT=5433 \
        .venv/bin/python manage.py check --deploy --fail-level ERROR
'

echo
if [ "$fail" -eq 0 ]; then
    printf '\033[32mGreen under CI'"'"'s conditions.\033[0m\n'
else
    printf '\033[31mRED under CI'"'"'s conditions — and green locally is not an argument.\033[0m\n'
fi
exit "$fail"
