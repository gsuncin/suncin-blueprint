#!/usr/bin/env bash
# Does the deploy path act on the WHOLE stack, and does everything that names
# the project agree on its name?
#
# WHY THIS FILE EXISTS. `deploy-remote.sh` used to write the literal list
# `bff web auth svc-example` four times — for the rollback digest capture, the
# recreate, the health wait and the rollback recreate. Add a microservice and no
# copy of the list learns about it: a deploy starts part of the stack and
# reports success, silently, because a loop over a list that does not mention a
# service cannot fail on it. That list was also already wrong — it omitted
# `worker`, so a rollback left the worker on the image the release had just
# proved broken.
#
# Every instance of this bug has been something naming its subjects by hand
# while the world grew a subject. So this check does not contain a service list.
# It derives the same set from two independent places and fails when they
# disagree:
#
#   A — the production compose TEMPLATE says which service takes an
#       `${image_*}` variable, i.e. which images this project builds rather
#       than pulls from a public registry at a version Terraform pins.
#   B — `deploy-remote.sh --print-services`, the deploy's own derivation, run
#       on the RENDERED production compose file, which by then names a registry
#       host rather than a variable.
#
# Different sources, different parsers, different signals. A bug in one does not
# hide in the other, which is what stops this from being a tautology — an
# assertion computed and never read.
#
# Run it locally exactly as CI does:
#
#   terraform -chdir=acme-tf/tests/render init -backend=false
#   terraform -chdir=acme-tf/tests/render apply -auto-approve
#   terraform -chdir=acme-tf/tests/render output -raw compose_file > /tmp/prod-compose.yml
#   .github/scripts/check-deploy-contract.sh /tmp/prod-compose.yml
#
# It lives in CI and not only in a Makefile target on purpose: a local command
# whose name promises a check nobody runs is worse than no command.
set -uo pipefail

cd "$(dirname "$0")/../.."

COMPOSE_RENDERED="${1:-}"
if [ -z "$COMPOSE_RENDERED" ] || [ ! -s "$COMPOSE_RENDERED" ]; then
    echo "usage: $0 <rendered production compose file>" >&2
    echo "  render it with: terraform -chdir=acme-tf/tests/render output -raw compose_file" >&2
    exit 2
fi

DEPLOY=.github/scripts/deploy-remote.sh
TEMPLATE=acme-tf/modules/app-stack/templates/docker-compose.yml.tftpl

fail=0
pass() { printf '  ok    %s\n' "$1"; }
fault() { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "The deploy path covers the whole stack"
echo

# --- 0. Dev and production run the same set of services ----------------------
# Section 1 below derives its two lists from the production template and from a
# render OF that template, so both would shrink together if a service were
# simply deleted from it. This is the check that closes that: the dev compose
# file is where a service appears first, and a service can live there for weeks
# while the production template has never heard of it. It is the service-level
# twin of the dev-vs-production router comparison in verify-isolation.sh, and it
# exists for the same reason — the two files are maintained by hand and a
# comment is all that keeps them in step.
echo "0. Dev and production declare the same services"

compose_services() {
    awk '
        /^[[:space:]]*#/ { next }
        /^services:[[:space:]]*$/ { in_services = 1; next }
        /^[^[:space:]]/ { in_services = 0 }
        in_services && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ {
            name = $1; sub(/:$/, "", name); print name
        }
    ' "$1" | sort -u
}

dev_services="$(compose_services docker-compose.yml)"
prod_services="$(compose_services "$TEMPLATE")"

if [ -z "$dev_services" ] || [ -z "$prod_services" ]; then
    fault "one of the two compose files yielded no services at all — the parse is broken, so this fails rather than passing"
elif [ "$dev_services" = "$prod_services" ]; then
    pass "$(printf '%s' "$dev_services" | tr '\n' ' ')"
else
    fault "the dev stack and the production template do not run the same services.
< docker-compose.yml    > $TEMPLATE
$(diff <(printf '%s\n' "$dev_services") <(printf '%s\n' "$prod_services") || true)"
fi

# --- 1. Which services does this project build an image for? -----------------
echo
echo "1. The service list, derived twice"

# Service -> image variable, from the template. Only the two-space-indented
# keys directly under `services:` are service names; `image:` and `networks:`
# are indented further, and `volumes:`/`networks:` at column 0 end the block.
#
# A service whose `image:` is a literal (traefik, postgres, rabbitmq, minio)
# is deliberately NOT one of these: the deploy does not build it, and re-tagging
# it with an application commit would ask the box to pull an image that does not
# exist.
template_pairs="$(awk '
    /^[[:space:]]*#/ { next }
    /^services:[[:space:]]*$/ { in_services = 1; next }
    /^[^[:space:]]/ { in_services = 0 }
    !in_services { next }
    /^  [A-Za-z0-9._-]+:[[:space:]]*$/ { svc = $1; sub(/:$/, "", svc); next }
    svc != "" && $1 == "image:" && $2 ~ /^\$\{image_[a-z_]+\}$/ {
        variable = $2
        sub(/^\$\{/, "", variable)
        sub(/\}$/, "", variable)
        print svc, variable
    }
' "$TEMPLATE")"

if [ -z "$template_pairs" ]; then
    fault "could not read any \${image_*} service out of $TEMPLATE — this check cannot run, so it fails rather than passing"
    echo
    echo "FAIL — see above."
    exit 1
fi

expected_services="$(printf '%s\n' "$template_pairs" | awk 'NF { print $1 }' | sort -u)"

# The deploy's own derivation, run by the deploy's own code. `--print-services`
# touches no docker, no sudo and no box, which is what makes it safe to call
# from a runner — and calling it is what keeps this check from grading a second
# copy of the parser that could agree with the same bug.
#
# `pipefail` is what makes the `if !` below read the deploy's exit status rather
# than sort's, which is why it is in this script's `set` line.
if ! derived_services="$("$DEPLOY" --print-services "$COMPOSE_RENDERED" 2>&1 | sort -u)" \
   || [ -z "$derived_services" ]; then
    fault "$DEPLOY --print-services failed or printed nothing:
$derived_services"
elif [ "$derived_services" = "$expected_services" ]; then
    pass "the deploy covers $(printf '%s' "$expected_services" | tr '\n' ' ')"
else
    fault "the deploy's service list and the production compose template disagree.
< $TEMPLATE    > deploy-remote.sh --print-services
$(diff <(printf '%s\n' "$expected_services") <(printf '%s\n' "$derived_services") || true)"
fi

# --- 2. The negative control --------------------------------------------------
# Everything above would also pass if `--print-services` ignored the file it is
# handed and printed a hand-typed list that happened to be complete today —
# which is the bug one iteration later. Take a service out of a COPY of the
# compose file; the derived list must lose exactly that service and nothing
# else. A check that cannot fail proves nothing.
echo
echo "2. The derivation reads the file it is given"

victim="$(printf '%s\n' "$expected_services" | tail -1)"
mutant="$(mktemp)"
trap 'rm -f "$mutant"' EXIT

awk -v drop="$victim" '
    $0 ~ "^  " drop ":[[:space:]]*$" { skipping = 1; next }
    skipping && /^  [A-Za-z0-9._-]+:[[:space:]]*$/ { skipping = 0 }
    skipping && /^[^[:space:]]/ { skipping = 0 }
    !skipping
' "$COMPOSE_RENDERED" > "$mutant"

if [ ! -s "$mutant" ] || [ "$(wc -l < "$mutant")" -ge "$(wc -l < "$COMPOSE_RENDERED")" ]; then
    fault "removing $victim from a copy of the compose file changed nothing — the mutation itself did not work, so this control proves nothing"
else
    mutated_services="$("$DEPLOY" --print-services "$mutant" 2>&1 | sort -u)"
    want="$(printf '%s\n' "$expected_services" | grep -vx "$victim")"
    if [ "$mutated_services" = "$want" ]; then
        pass "dropping $victim from the compose file drops it from the derived list"
    else
        fault "with $victim removed from the compose file the derivation still reports:
$mutated_services
It is not reading the file it is given."
    fi
fi

# --- 3. Every image CI publishes is an image the box is told to pull ----------
# The other half of the same question. A complete service list still deploys
# nothing if the reference it pulls is not the reference the build pushed —
# `docker compose pull` 404s and the deploy stops, which is loud, but it stops
# on every release until the two names match.
echo
echo "3. Image names: what CI publishes vs what the tfvars example pulls"

# One `images:` line and one `context:` line per docker-*.yml, paired by file.
# The context is carried along because section 3b needs it: the image name is
# NOT always the source directory — `acme-gateway-auth` is built from
# `acme-gateway/auth` — and guessing would report a false defect.
published_pairs=""
for workflow in .github/workflows/docker-*.yml; do
    images="$(sed -nE 's#^[[:space:]]*images: ghcr\.io/.*/(.+)$#\1#p' "$workflow")"
    context="$(sed -nE 's#^[[:space:]]*context: \./(.+)$#\1#p' "$workflow")"
    [ -n "$images" ] || continue
    case "${images}|${context}" in
        '${{ matrix.service }}|${{ matrix.service }}')
            # docker-svc.yml builds a matrix over the acme-svc-* directories,
            # so the images it publishes are those directory names and each is
            # its own context. Expanding it rather than skipping it is the
            # point: a check that quietly ignored a matrix would report success
            # about exactly the services most likely to be missing.
            published_pairs="${published_pairs}$(ls -d acme-svc-*/ 2>/dev/null | sed -E 's#(.+)/#\1 \1#')
"
            ;;
        *'{{'*)
            fault "cannot tell what $workflow publishes or where from, so it fails rather than being skipped: images=[$images] context=[$context]"
            ;;
        *)
            published_pairs="${published_pairs}${images} ${context}
"
            ;;
    esac
done

if [ -z "$published_pairs" ]; then
    fault "no docker-*.yml workflow declares an image — this check cannot run"
fi

published="$(printf '%s' "$published_pairs" | awk 'NF { print $1 }' | sort -u)"
# The committed tfvars example is the template every environment is filled in
# from, so it is where a wrong image name is introduced and then copied.
pulled="$(sed -nE 's#^image_[a-z_]+[[:space:]]*=[[:space:]]*"[^"]*/([^:"]+):[^"]*".*#\1#p' \
          acme-tf/envs/*/terraform.tfvars.example | sort -u)"

if [ -z "$published" ] || [ -z "$pulled" ]; then
    fault "one side of the image-name comparison came back empty — it cannot run, so it fails"
elif [ "$published" = "$pulled" ]; then
    pass "$(printf '%s' "$published" | tr '\n' ' ')"
else
    fault "the images CI publishes and the images the tfvars example tells the box to pull are not the same set.
< published by .github/workflows/docker-*.yml    > pulled per acme-tf/envs/*/terraform.tfvars.example
$(diff <(printf '%s\n' "$published") <(printf '%s\n' "$pulled") || true)"
fi

# --- 3b. Every service the deploy waits for can report health ----------------
# The deploy blocks on `.State.Health.Status = healthy` for each service in the
# list, because recreated containers get new IPs and Traefik holds the old ones
# until its own healthCheck re-resolves them. A service with no healthcheck
# ANYWHERE reports `unknown` forever: the deploy waits out its 120 seconds and
# then rolls back a release that was fine. So widening the list — which deriving
# it does, `worker` included — is only safe if every member can answer.
#
# Two places count, and there is one case where only the first will do: a
# service that overrides the image's `command:` is no longer running the process
# the image's HEALTHCHECK was written for, so the image's answer is worse than
# no answer. `worker` is exactly that — it reuses the bff image, whose
# HEALTHCHECK curls port 8000, and runs Celery, which listens on nothing. It
# would sit `unhealthy` rather than `unknown`, and the deploy would roll back
# every release. So: an explicit `healthcheck:`, or an image `HEALTHCHECK` and
# no command override.
echo
echo "3b. Everything the deploy waits for can answer"

service_image_and_health="$(awk '
    /^[[:space:]]*#/ { next }
    /^services:[[:space:]]*$/ { in_services = 1; next }
    /^[^[:space:]]/ { if (svc != "") { emit(); svc = "" } ; in_services = 0 }
    !in_services { next }
    /^  [A-Za-z0-9._-]+:[[:space:]]*$/ {
        if (svc != "") emit()
        svc = $1; sub(/:$/, "", svc); img = "-"; health = "no"; command = "no"; next
    }
    $1 == "image:" { img = $2 }
    $1 == "healthcheck:" { health = "yes" }
    $1 == "command:" { command = "yes" }
    END { if (svc != "") emit() }
    function emit() { print svc, img, health, command }
' "$COMPOSE_RENDERED")"

silent=""
while IFS= read -r service; do
    row="$(printf '%s\n' "$service_image_and_health" | awk -v s="$service" '$1 == s')"
    [ -n "$row" ] || { silent="${silent} ${service}:not-in-compose"; continue; }
    if [ "$(printf '%s' "$row" | awk '{print $3}')" = "yes" ]; then
        continue
    fi
    if [ "$(printf '%s' "$row" | awk '{print $4}')" = "yes" ]; then
        silent="${silent} ${service}:overrides-command-so-needs-its-own-healthcheck"
        continue
    fi
    # No compose healthcheck, so the image must carry one. Which Dockerfile
    # that is comes from the build workflow's own `context:`, not from the
    # image name: `acme-gateway-auth` is built from `acme-gateway/auth`, and
    # assuming name == directory reports a defect that is not there.
    image="$(printf '%s' "$row" | awk '{print $2}')"
    name="${image##*/}"
    name="${name%%:*}"
    context="$(printf '%s\n' "$published_pairs" | awk -v n="$name" '$1 == n { print $2 }')"
    if [ -z "$context" ]; then
        silent="${silent} ${service}:no-build-workflow-publishes-${name}"
    elif [ ! -f "${context}/Dockerfile" ]; then
        silent="${silent} ${service}:no-${context}/Dockerfile"
    elif ! grep -q '^HEALTHCHECK' "${context}/Dockerfile"; then
        silent="${silent} ${service}:${context}-has-no-HEALTHCHECK"
    fi
done <<< "$derived_services"

if [ -n "$silent" ]; then
    fault "these are in the release list but cannot report health, so the deploy would wait 120s and roll back a good release:${silent}"
else
    pass "every service in the release list has a compose healthcheck or an image HEALTHCHECK"
fi

# --- 4. PROJECT and var.project are one name ---------------------------------
# The production compose template names containers `${project}-<service>` from
# the Terraform variable, and the deploy looks them up as
# `${PROJECT}-${service}` to capture the rollback digests. Change one and not
# the other and `docker inspect` matches nothing, `rollback-images` is written
# empty, and a failed deploy has nothing to restore — the only safety net in
# the deploy path, lost silently. Same failure shape as the service list above,
# which is why it is checked here rather than trusted to a comment.
echo
echo "4. PROJECT travels with var.project"

project_names=""
note_project() { project_names="${project_names}$1 $2
"; }

note_project "$DEPLOY" \
    "$(sed -nE 's/^PROJECT="\$\{PROJECT:-([A-Za-z0-9_-]+)\}".*/\1/p' "$DEPLOY")"
note_project .github/scripts/diagnose-remote.sh \
    "$(sed -nE 's/^PROJECT="\$\{PROJECT:-([A-Za-z0-9_-]+)\}".*/\1/p' .github/scripts/diagnose-remote.sh)"

for tf in acme-tf/modules/app-stack/variables.tf acme-tf/envs/*/variables.tf; do
    [ -f "$tf" ] || continue
    note_project "$tf" "$(sed -nE '/^variable "project"/,/^}/ s/^[[:space:]]*default[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$tf")"
done

for tfvars in acme-tf/envs/*/terraform.tfvars.example; do
    [ -f "$tfvars" ] || continue
    note_project "$tfvars" "$(sed -nE 's/^project[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$tfvars")"
done

unreadable="$(printf '%s' "$project_names" | awk 'NF < 2 { print $1 }')"
distinct="$(printf '%s' "$project_names" | awk '{ print $2 }' | sort -u)"

if [ -n "$unreadable" ]; then
    fault "no project name could be read out of these, so the comparison cannot run:
$unreadable"
elif [ "$(printf '%s\n' "$distinct" | wc -l | tr -d ' ')" -ne 1 ]; then
    fault "these disagree about the project name:
$(printf '%s' "$project_names")"
else
    pass "every file that names the project says '$distinct'"
fi

# --- 5. .github/SECRETS.md names every secret a workflow reads ---------------
# The manifest IS the template — a repository secret cannot have a committed
# `.example` file. A workflow reading a secret nobody was told to set fails at
# run time, which for a deploy means in production, on a release.
echo
echo "5. SECRETS.md is complete"

# Comments stripped first, and that is load-bearing: a workflow comment
# explaining that some secret was REMOVED and the value is generated in the step
# instead would otherwise read as usage, and demand a row for a secret nothing
# reads. That is the opposite failure.
secrets_used="$(sed 's/#.*//' .github/workflows/*.yml \
                | grep -ohE 'secrets\.[A-Z0-9_]+' | sed 's/^secrets\.//' | sort -u)"

if [ -z "$secrets_used" ]; then
    fault "no workflow appears to read a secret — the extraction is broken, so this fails rather than passing"
else
    undocumented=""
    while IFS= read -r name; do
        grep -q "$name" .github/SECRETS.md || undocumented="${undocumented} ${name}"
    done <<< "$secrets_used"
    if [ -n "$undocumented" ]; then
        fault ".github/SECRETS.md has no row for:${undocumented}"
    else
        pass "$(printf '%s\n' "$secrets_used" | wc -l | tr -d ' ') secrets read by a workflow, all documented"
    fi
fi

# --- 6. deploy-prod.yml listens to every build, and fails closed -------------
# A deploy pins every release image to one tag, and its preflight skips until
# all of them exist. A build it does not listen to is a release that waits for
# the next unrelated build to deploy (graav-app's 2026-10-12 incident).
echo
echo "6. deploy-prod.yml listens to every build and to the retag"

listened="$(sed -nE 's/^[[:space:]]*workflows: \[(.*)\][[:space:]]*$/\1/p' .github/workflows/deploy-prod.yml \
            | tr ',' '\n' | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' | awk 'NF' | sort -u)"
builders="$(for wf in .github/workflows/docker-*.yml .github/workflows/retag-unchanged.yml; do
                [ -f "$wf" ] && sed -nE 's/^name:[[:space:]]*(.+)$/\1/p' "$wf" | head -1
            done | sort -u)"
if [ -z "$listened" ] || [ -z "$builders" ]; then
    fault "could not read deploy-prod.yml's workflow_run list or the build names"
elif [ "$listened" = "$builders" ]; then
    pass "workflow_run lists: $(printf '%s' "$listened" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
else
    fault "deploy-prod.yml's workflow_run list and the build workflows disagree:
$(diff <(printf '%s\n' "$listened") <(printf '%s\n' "$builders") || true)"
fi

# The preflight's tag is the 7-character sha of the commit the build built, the
# same form docker/metadata-action pushes; never github.sha, which in a
# workflow_run event is the default branch's tip.
if grep -qF 'tag="sha-${HEAD_SHA:0:7}"' .github/workflows/deploy-prod.yml \
   && ! grep -qF "format('sha-{0}', github.sha)" .github/workflows/deploy-prod.yml; then
    pass "the tag is sha-<7> of workflow_run.head_sha"
else
    fault "deploy-prod.yml does not derive the tag from workflow_run.head_sha's first 7 characters"
fi

# `for x in $(cmd)` discards cmd's exit status, so a failing release-images.sh
# would read as "no images, none missing, ready".
if grep -qE 'for [a-z_]+ in \$\(\.github/scripts/release-images\.sh' .github/workflows/deploy-prod.yml; then
    fault "deploy-prod.yml loops over \$(release-images.sh) directly, which hides its failure"
else
    pass "release-images.sh's exit status is checked before the loop"
fi

# Each docker-*.yml publishes from build-and-push alone, and never on a PR.
publish_faults=0
for wf in .github/workflows/docker-*.yml; do
    if grep -qE '^  packages: write' "$wf"; then
        fault "$wf grants packages: write to every job; it belongs on build-and-push alone"
        publish_faults=$((publish_faults + 1))
    fi
    if ! sed -n '/^  build-and-push:/,/^    steps:/p' "$wf" | grep -q "github.event_name != 'pull_request'"; then
        fault "$wf's build-and-push can run on a pull request"
        publish_faults=$((publish_faults + 1))
    fi
done
[ "$publish_faults" -eq 0 ] && pass "every build-and-push holds packages: write alone and never runs on a pull request"

echo
if [ "$fail" -eq 0 ]; then
    echo "PASS — the deploy path covers the whole stack."
else
    echo "FAIL — see above. Do not retype the list with the missing names on it; that is the bug one iteration later."
fi
exit "$fail"
