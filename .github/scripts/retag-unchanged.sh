#!/usr/bin/env bash
# Give every image whose source did not change this commit's tag, without
# rebuilding it.
#
#   OWNER=<registry owner> BEFORE=<push's before> DISPATCH_FILE=<path> \
#       .github/scripts/retag-unchanged.sh
#
# WHY THIS EXISTS. A deploy pins all five images to one `sha-<7>` tag, and the
# builds are path-filtered, so a release that touches only acme-web publishes one
# image of five and the deploy skips until the other four are dispatched by hand,
# tests included: 19 dispatches in October (graav-app R-2026-10-30-d3df6f). An image whose
# paths did not change is the same image, so it gets the new tag on the manifest
# it already has. `docker buildx imagetools create` copies the multi-arch manifest
# and rebuilds nothing, in seconds.
#
# A WRONG TAG IS WORSE THAN A MISSING ONE. A missing image is a skipped deploy. A
# wrong one is a service silently rolled back with every check green. So:
#
#   - The source is only ever the sha tag of an ancestor on main, found by
#     walking main. Floating tags are never read: images built by hand while CI
#     was dark never updated them, so one can point at an old build.
#     check-deploy-contract.sh fails if the floating tag's name appears here.
#   - A retag happens only when `git diff <ancestor> HEAD` over the build's own
#     paths is empty. Non-empty means that build is running or has failed: leave
#     the image missing, and the preflight skips.
#   - "Has failed" must not be forever. When BEFORE shows this push did not
#     touch those paths, GitHub fired no build for it, so the change came in an
#     earlier push whose build never published, and no later push that misses
#     the paths will fire it again. That workflow is written to DISPATCH_FILE,
#     once each, and the workflow dispatches it on main after this script
#     succeeds: the build of this commit writes this tag, and its completion
#     triggers the deploy. Without BEFORE the two cannot be told apart, so the
#     image is only named, with the workflow to dispatch by hand.
#   - Registry errors stop the run. `denied` is not evidence of absence, and
#     reading it as absence would walk past the real ancestor to an older one.
#
# A DOCS-ONLY MERGE DOES NOTHING. If no image is built for this commit, retagging
# all five would deploy a release with nothing in it and restart production for
# no reason. "Built" has to mean what GitHub means, and GitHub filters a push
# against its `before`, so two questions are asked of each repository: does it
# differ from BEFORE, which says its build fires, and does it differ from its
# newest tag? A revert is why both are needed. Release A changes bff and web, the
# bff suite goes red, web publishes; R reverts bff alone. bff now equals an old
# tag and web equals A, so the tag walk alone reads "nothing built", while GitHub
# has fired bff's build, and the deploy would stall forever on tags never written.
#
# BEFORE is the push's `github.event.before`. All zeros (a new branch) or a commit
# that is not an ancestor (a force-push) has nothing to say, and the tag walk
# answers alone.
#
# Two phases, so a failed derivation retags nothing at all.
#
# DERIVED, NOT LISTED (specs/README.md). The repositories come from
# release-images.sh, the parse the preflight uses; the workflow that publishes
# each, and that workflow's on.push.paths, are read from .github/workflows, and
# anything that comes back empty stops the run.
#
# Runs on bash 3.2, as every script here does: macOS is where it is tested.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

# How far back to look. Long enough for a month of releases; a repository with
# no tag this far back is one a human should look at, not one to guess about.
WALK_LIMIT=100

fail() {
    echo "::error::$1" >&2
    exit 1
}

owner="$(printf '%s' "${OWNER:-}" | tr '[:upper:]' '[:lower:]')"
[ -n "$owner" ] || fail "OWNER must be set"

# Where the stranded builds are listed for the workflow to dispatch. Required,
# and emptied now: a list left by an earlier run is not this run's answer, and a
# list with nowhere to go would be a stranded image nobody is told about.
dispatch_file="${DISPATCH_FILE:-}"
[ -n "$dispatch_file" ] || fail "DISPATCH_FILE must name the file the stranded builds are listed in"
: > "$dispatch_file" || fail "cannot write ${dispatch_file}"

[ "$(git rev-parse --is-shallow-repository)" = false ] \
    || fail "a shallow clone cannot walk main; the workflow's checkout needs fetch-depth: 0"
head_commit="$(git rev-parse --verify --quiet 'HEAD^{commit}')" || fail "cannot read HEAD"
parent="$(git rev-parse --verify --quiet 'HEAD^1^{commit}')" || fail "HEAD has no parent to walk from"

# The first seven characters, as docker/metadata-action and the preflight cut
# them. Not `git rev-parse --short=7`, which grows when seven is ambiguous and
# would name a tag nothing published.
sha_tag() {
    printf 'sha-%s' "$(printf '%s' "$1" | cut -c1-7)"
}

# Loads the workflow's on.push.paths into the array `paths`, as pathspecs.
#
# awk rather than a YAML parser, which neither the runner image nor a laptop can
# be assumed to have. Comment lines between entries are skipped (docker-bff.yml
# has them), and the next event key ends the list, so on.pull_request.paths are
# not read.
#
# `:(glob)` makes `*` stop at a slash and `/**` match everything under a
# directory, which is what GitHub's filter means by them, and it is why
# `acme-svc-*/**` works here as it does in the build. A negated filter has no
# faithful translation, so it stops the run.
load_paths() {
    local workflow="$1" entries entry
    entries="$(awk '
        /^[[:space:]]*#/ { next }
        /^on:[[:space:]]*$/ { in_on = 1; next }
        in_on && /^[^[:space:]]/ { in_on = 0; in_push = 0; in_paths = 0 }
        in_on && /^  [A-Za-z_]+:/ { in_push = ($1 == "push:"); in_paths = 0; next }
        in_push && /^    [A-Za-z_]+:/ { in_paths = ($1 == "paths:"); next }
        in_paths && /^ +- / {
            entry = $0
            sub(/^ +- */, "", entry)
            sub(/[[:space:]]+#.*$/, "", entry)
            sub(/[[:space:]]+$/, "", entry)
            gsub(/^["'\'']|["'\'']$/, "", entry)
            print entry
        }
    ' "$workflow")"
    [ -n "$entries" ] || return 1
    paths=()
    while IFS= read -r entry; do
        case "$entry" in
            '!'*)
                echo "::error::$workflow has a negated path filter this script cannot honour: $entry" >&2
                return 1
                ;;
        esac
        paths+=(":(glob)$entry")
    done <<< "$entries"
}

# Does this workflow's `images:` line publish this repository? A matrix image is
# the directory of that name, when the workflow's own path filter covers it, so
# the acme-svc-*/** glob decides what docker-svc.yml publishes. A here-string and
# not a pipe into `grep -q`: grep stopping early would be a SIGPIPE on the writer,
# and pipefail would read a match as a failure.
workflow_publishes() {
    local workflow="$1" repo="$2" image files
    image="$(sed -nE 's#^[[:space:]]*images: ghcr\.io/.*/(.+)$#\1#p' "$workflow")"
    case "$image" in
        "$repo")
            return 0
            ;;
        '${{ matrix.service }}')
            [ -d "$repo" ] && load_paths "$workflow" || return 1
            files="$(git ls-files -- "${paths[@]}")"
            grep -q "^${repo}/" <<< "$files"
            ;;
        *)
            return 1
            ;;
    esac
}

# The same reading of `docker manifest inspect` as the preflight in
# deploy-prod.yml: published, or not published, or it stops the run. stdin is
# closed because callers sit inside `while read` loops, and anything that reads
# stdin there would eat the rest of the list and end the run at exit 0.
tag_exists() {
    local ref="$1" out
    if out="$(docker manifest inspect "$ref" 2>&1 > /dev/null < /dev/null)"; then
        return 0
    fi
    if grep -qiE 'manifest unknown|no such manifest|not found' <<< "$out"; then
        return 1
    fi
    fail "could not ask the registry about ${ref}: ${out}"
}

# --- Phase 1: resolve every repository, or stop ------------------------------
# Assigned first, then checked: `for x in $(cmd)` throws away cmd's exit status.
repos="$(.github/scripts/release-images.sh | awk '{ print $2 }' | sort -u)" \
    || fail "release-images.sh failed"
[ -n "$repos" ] || fail "no release images"

resolved=""
for repo in $repos; do
    publisher=""
    for workflow in .github/workflows/docker-*.yml; do
        [ -f "$workflow" ] || continue
        if workflow_publishes "$workflow" "$repo"; then
            [ -z "$publisher" ] || fail "both $publisher and $workflow publish $repo"
            publisher="$workflow"
        fi
    done
    [ -n "$publisher" ] || fail "no docker-*.yml publishes $repo"
    load_paths "$publisher" || fail "$publisher publishes $repo and has no usable on.push.paths"
    resolved="${resolved}${repo} ${publisher}
"
done

# --- Phase 2: what happened to each one at this commit? ----------------------
head_tag="$(sha_tag "$head_commit")"
ancestors="$(git rev-list --first-parent --max-count="$WALK_LIMIT" "$parent")" \
    || fail "cannot walk main from $parent"

before="${BEFORE:-}"
case "$before" in
    *[!0]*) ;;
    *) before="" ;;
esac
if [ -n "$before" ] && ! git merge-base --is-ancestor "$before" "$head_commit" 2> /dev/null; then
    echo "${before} is not an ancestor of this commit, so the tag walk answers alone"
    before=""
fi

something_built=0
candidates=""
dispatch=""
while read -r repo publisher; do
    [ -n "$repo" ] || continue
    image="ghcr.io/${owner}/${repo}"

    if tag_exists "${image}:${head_tag}"; then
        echo "${repo}: ${head_tag} already exists, leaving it"
        something_built=1
        continue
    fi

    load_paths "$publisher" || fail "$publisher lost its paths"

    # GitHub has fired this build, so it owns the tag, even when the source now
    # matches an older one. Copying that older image here would let the deploy
    # run before this build's suite has said anything.
    changed_in_push=unknown
    if [ -n "$before" ]; then
        git diff --quiet "$before" "$head_commit" -- "${paths[@]}"
        case $? in
            0) changed_in_push=no ;;
            1)
                echo "${repo}: changed in this push, so its build owns this tag"
                something_built=1
                continue
                ;;
            *)
                fail "git diff against BEFORE failed for ${repo}"
                ;;
        esac
    fi

    found=""
    for commit in $ancestors; do
        if tag_exists "${image}:$(sha_tag "$commit")"; then
            found="$commit"
            break
        fi
    done
    if [ -z "$found" ]; then
        echo "::notice title=not retagged::${repo} has no sha tag on the last ${WALK_LIMIT} commits of main, so there is nothing safe to copy. Dispatch its build on main."
        continue
    fi

    git diff --quiet "$found" "$head_commit" -- "${paths[@]}"
    case $? in
        0)
            echo "${repo}: unchanged since $(sha_tag "$found")"
            candidates="${candidates}${repo} $(sha_tag "$found")
"
            ;;
        1)
            # Changed since its newest tag, and (when BEFORE says so) not in this
            # push. Then the change landed earlier and its build failed or was
            # cancelled, and no push that misses its paths will ever fire it
            # again: the image stays missing at every later commit and nothing
            # deploys until a human dispatches it (2026-10-31 to 11-09, auth).
            # So the build is dispatched on main, where it builds main's tip (this commit, or a newer one)
            # and writes this tag. Still "built", so the others are retagged.
            workflow_name="$(basename "$publisher")"
            if [ "$changed_in_push" = no ]; then
                echo "::warning title=stranded build dispatched::${repo} changed after $(sha_tag "$found") and no build ever published it, and this push does not fire one, so ${workflow_name} is dispatched on main to build ${head_tag}, unless a run of it is already in flight"
                dispatch="${dispatch}${workflow_name}
"
            else
                echo "${repo}: changed since $(sha_tag "$found"), so its build owns this tag. If no build of ${head_tag} is running, an earlier one failed: dispatch ${workflow_name} on main"
            fi
            something_built=1
            ;;
        *)
            fail "git diff failed for ${repo}"
            ;;
    esac
done <<< "$resolved"

if [ "$something_built" -eq 0 ]; then
    echo "nothing is built for this commit, so nothing is retagged and nothing deploys"
    exit 0
fi

while read -r repo source_tag; do
    [ -n "$repo" ] || continue
    image="ghcr.io/${owner}/${repo}"
    echo "retagging ${image}:${source_tag} as ${head_tag}"
    docker buildx imagetools create -t "${image}:${head_tag}" "${image}:${source_tag}" < /dev/null \
        || fail "could not retag ${image}:${source_tag}"
done <<< "$candidates"

# Last, so a run that failed above lists nothing. Once per workflow:
# docker-svc.yml publishes two images, and a second dispatch would cancel the
# first (its concurrency group cancels in progress).
if [ -n "$dispatch" ]; then
    printf '%s' "$dispatch" | sort -u > "$dispatch_file" || fail "cannot write ${dispatch_file}"
fi
