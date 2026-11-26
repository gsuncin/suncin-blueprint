#!/usr/bin/env bash
# Which image repositories does a release publish?
#
#   .github/scripts/release-images.sh
#
# Prints "<build context> <repository>" per line, e.g. `acme-bff acme-bff`, one
# per image a .github/workflows/docker-*.yml publishes. docker-svc.yml builds a
# matrix over the acme-svc-* directories, so each of those is listed by name.
# Four repositories for five services today, because `worker` runs the bff image.
#
# deploy-prod.yml's preflight checks that every one exists in ghcr at the
# release tag before it connects to the box. check-deploy-contract.sh section 3
# derives the same set the same way and compares it with what the tfvars
# example tells the box to pull, so the two cannot drift apart unnoticed.
set -euo pipefail

cd "$(dirname "$0")/../.."

pairs=""
for workflow in .github/workflows/docker-*.yml; do
    images="$(sed -nE 's#^[[:space:]]*images: ghcr\.io/.*/(.+)$#\1#p' "$workflow")"
    context="$(sed -nE 's#^[[:space:]]*context: \./(.+)$#\1#p' "$workflow")"
    [ -n "$images" ] || continue
    case "${images}|${context}" in
        '${{ matrix.service }}|${{ matrix.service }}')
            pairs="${pairs}$(ls -d acme-svc-*/ 2>/dev/null | sed -E 's#(.+)/#\1 \1#')
"
            ;;
        *'{{'*)
            echo "cannot tell what ${workflow} publishes: images=[${images}] context=[${context}]" >&2
            exit 1
            ;;
        *)
            pairs="${pairs}${context} ${images}
"
            ;;
    esac
done

# Fail closed: an empty list would let the preflight "confirm" zero images and
# deploy.
pairs="$(printf '%s' "$pairs" | awk 'NF' | sort -u)"
if [ -z "$pairs" ]; then
    echo "no docker-*.yml workflow publishes an image" >&2
    exit 1
fi
printf '%s\n' "$pairs"
