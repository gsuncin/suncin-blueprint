#!/usr/bin/env bash
# Does every pull-request workflow skip a draft, and run again when it is
# marked ready? (ported from graav-app PR #504)
#
# WHY. A release PR stays open while the integration branch fills up, and every push to
# it is a `synchronize`. Without a draft guard each one re-ran both suites:
# 22 runs and ~600 billed minutes in graav-app in November 2026. One workflow had
# the guard and everything else did not, so the rule held in one file and
# RELEASES.md described it as if it held in all of them.
#
# DERIVED, NOT LISTED. The workflows come from their own `pull_request:`
# trigger, so a new one is checked the day it is added. For each:
#   - `types:` under `pull_request:` names `ready_for_review`, or marking the
#     draft ready would run nothing at all;
#   - every job with no `needs:` carries `!github.event.pull_request.draft` in
#     its `if:`. A job with `needs:` is skipped with what it needs.
# A trigger spelled in a form this cannot read (`on: pull_request`,
# `on: [push, pull_request]`) fails rather than passing unread.
#
# Usage: ./scripts/check-ci-skips-drafts.sh [workflow-dir]
set -uo pipefail

DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/.github/workflows}"
GUARD='!github.event.pull_request.draft'

faults=0
checked=0
fault() { printf '  FAIL %s\n' "$1"; faults=$((faults + 1)); }

for wf in "$DIR"/*.yml; do
    name="$(basename "$wf")"

    if grep -qE '^on:.*pull_request' "$wf"; then
        fault "$name: pull_request is in an inline 'on:' this check cannot read; use the block form"
        continue
    fi
    grep -qE '^  pull_request:' "$wf" || continue
    checked=$((checked + 1))

    # The pull_request block: from its key to the next key at indent 2 or less.
    types="$(awk '
        /^  pull_request:/ { inpr = 1; next }
        inpr && /^ {0,2}[^ #]/ { inpr = 0 }
        inpr && /^    types:/ { print }
    ' "$wf")"
    case "$types" in
        *ready_for_review*) ;;
        *) fault "$name: pull_request has no 'types:' naming ready_for_review, so marking a draft ready runs nothing" ;;
    esac

    # One line per top-level job: "<job> <has-needs> <has-guard>".
    while read -r job needs guarded; do
        [ -n "$job" ] || continue
        if [ "$needs" = 0 ] && [ "$guarded" = 0 ]; then
            fault "$name: job '$job' has no needs and no draft guard, so it runs on every push to a draft PR"
        fi
    done < <(awk -v guard="$GUARD" '
        function flush() { if (job != "") print job, needs, guarded }
        /^jobs:/ { injobs = 1; next }
        injobs && /^[^ #]/ { flush(); job = ""; injobs = 0 }
        injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
            flush(); job = $1; sub(/:$/, "", job); needs = 0; guarded = 0; next
        }
        injobs && job != "" && /^    needs:/ { needs = 1 }
        injobs && job != "" && /^    if:/ && index($0, guard) { guarded = 1 }
        END { flush() }
    ' "$wf")
done

if [ "$checked" -eq 0 ]; then
    fault "no workflow in $DIR has a pull_request trigger: the extraction is broken, so this fails rather than passing"
fi

if [ "$faults" -gt 0 ]; then
    printf '\n%d fault(s) across %d pull-request workflow(s)\n' "$faults" "$checked"
    exit 1
fi
printf 'ok   %d pull-request workflows skip drafts and run when marked ready\n' "$checked"
