#!/usr/bin/env bash
# Turn this boilerplate into your project.
#
#   ./scripts/init-project.sh my-app "My App"
#
# Renames directories, image names, container names, hostnames, database names
# and the log schema, then regenerates local secrets and runs the full suite to
# prove the derived project starts green.
#
# THE ONE HAZARD: "ACME" is also the name of the TLS certificate protocol.
# /acme/acme.json, certificatesResolvers.acme, acme_email and
# .well-known/acme-challenge all belong to Let's Encrypt and must survive
# untouched — renaming them produces a stack that starts fine and then cannot
# get a certificate, which is a bad afternoon. They are protected below.
set -euo pipefail

SLUG="${1:?usage: init-project.sh <slug> [\"Display Name\"]}"
DISPLAY="${2:-}"

if ! [[ "$SLUG" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
    echo "Slug must be lowercase letters, digits and hyphens, starting with a letter." >&2
    exit 1
fi

# Derive a display name if none was given: my-app -> My App
if [ -z "$DISPLAY" ]; then
    DISPLAY="$(echo "$SLUG" | tr '-' ' ' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')"
fi

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if [ ! -d acme-bff ]; then
    echo "No acme-* directories here. Has this already been initialised?" >&2
    exit 1
fi

echo "Renaming acme -> ${SLUG} (\"${DISPLAY}\")"
echo

SLUG="$SLUG" DISPLAY="$DISPLAY" python3 - <<'PY'
import os
import pathlib
import re
import shutil

slug = os.environ["SLUG"]
display = os.environ["DISPLAY"]
snake = slug.replace("-", "_")
upper = snake.upper()
root = pathlib.Path.cwd()

# Tokens that belong to the ACME/Let's Encrypt protocol, not to this project.
# Swapped for sentinels before the rename and restored afterwards.
PROTECTED = [
    "acme-challenge",
    "acme.json",
    "acme_email",
    "ACME_EMAIL",
    "/acme/",
    "acme:",            # certificatesResolvers.<name>.acme
    "acme/acme.json",
]

# Ordered longest-first so a shorter pattern cannot eat part of a longer one.
REPLACEMENTS = [
    ("acme-svc-example", f"{slug}-svc-example"),
    ("acme-gateway", f"{slug}-gateway"),
    ("acme-bff", f"{slug}-bff"),
    ("acme-web", f"{slug}-web"),
    ("acme-auth", f"{slug}-auth"),
    ("acme-tf", f"{slug}-tf"),
    ("acme-traefik", f"{slug}-traefik"),
    ("acme-worker", f"{slug}-worker"),
    ("acme-postgres", f"{slug}-postgres"),
    ("acme-rabbitmq", f"{slug}-rabbitmq"),
    ("acme/bff", f"{slug}/bff"),
    ("acme/web", f"{slug}/web"),
    ("acme/auth", f"{slug}/auth"),
    ("acme/svc-example", f"{slug}/svc-example"),
    ("acme.localhost", f"{slug}.localhost"),
    ("acme.test", f"{slug}.test"),
    ("acme.example.com", f"{slug}.example.com"),
    ("acme_scratch", f"{snake}_scratch"),
    ("acme.log.v1", f"{slug}.log.v1"),
    ("ACME_", f"{upper}_"),
    ("Acme", display),
    # Bare "acme" last, and only on a word boundary: it is the database name,
    # the database user, the Terraform project default and the RabbitMQ user.
    (re.compile(r"\bacme\b"), slug),
]

SKIP_DIRS = {".git", "node_modules", ".venv", "__pycache__", ".pytest_cache",
             "dist", "coverage", ".terraform", "playwright-report",
             "test-results", ".lighthouseci", "staticfiles"}

BINARY_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".ico", ".woff", ".woff2",
                   ".pdf", ".gz", ".zip", ".dump"}


def rewrite(text: str) -> str:
    # Protect first.
    for index, token in enumerate(PROTECTED):
        text = text.replace(token, f"\x00PROTECTED{index}\x00")

    for pattern, replacement in REPLACEMENTS:
        if isinstance(pattern, re.Pattern):
            text = pattern.sub(replacement, text)
        else:
            text = text.replace(pattern, replacement)

    for index, token in enumerate(PROTECTED):
        text = text.replace(f"\x00PROTECTED{index}\x00", token)

    return text


# --- 1. File contents ------------------------------------------------------
changed = 0
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if any(part in SKIP_DIRS for part in path.parts):
        continue
    if path.suffix.lower() in BINARY_SUFFIXES:
        continue
    # Never rewrite the generated .env: it holds live secrets and is regenerated.
    if path.name == ".env":
        continue
    # Never rewrite THIS script while it is running. Bash reads a script
    # incrementally from disk, so rewriting it mid-execution corrupts whatever
    # it has not read yet — the symptom is a syntax error on a line that was
    # perfectly valid when the run started. (Same family of bug as the stdin
    # trap documented in .github/scripts/deploy-remote.sh.)
    if path.name == "init-project.sh":
        continue

    try:
        original = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue

    updated = rewrite(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        changed += 1

print(f"  rewrote {changed} files")

# --- 2. Directory names ----------------------------------------------------
# Deepest first, so renaming a parent cannot invalidate a child's path.
renamed = 0
for path in sorted(root.rglob("acme-*"), key=lambda p: len(p.parts), reverse=True):
    if any(part in SKIP_DIRS for part in path.parts):
        continue
    new_name = path.name.replace("acme-", f"{slug}-", 1)
    target = path.with_name(new_name)
    if target.exists():
        continue
    shutil.move(str(path), str(target))
    renamed += 1

print(f"  renamed {renamed} paths")
PY

echo
echo "Regenerating local secrets"
rm -f .env
./scripts/gen-keys.sh > /dev/null
echo "  .env regenerated (the boilerplate's keys are gone)"

echo
echo "Checking nothing was missed"
# The protected ACME-protocol tokens are expected; anything else is a bug in
# the rename and would surface much later as a container that cannot be found.
LEFTOVER="$(grep -rniE '\bacme\b' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv \
    --exclude-dir=__pycache__ --exclude-dir=.terraform --exclude-dir=dist \
    --exclude-dir=.pytest_cache --exclude=.env --exclude=init-project.sh . 2>/dev/null \
    | grep -viE "acme\\.json|acme-challenge|acme_email|ACME_EMAIL|/acme/|certificatesResolver|letsencrypt|acme:|ACME challenge|ACME exists|security headers, ACME" || true)"

if [ -n "$LEFTOVER" ]; then
    echo "  WARNING: these still mention acme and may need a look:"
    printf '%s\n' "$LEFTOVER" | head -20
else
    echo "  clean — only the TLS protocol's own 'acme' remains"
fi

cat <<EOF

Done. ${DISPLAY} is ready.

Next:
  1. rm -rf .git && git init          # start your own history
  2. git config core.hooksPath .githooks
  3. make up                          # build, start, migrate, seed
  4. make test                        # prove it is green

Then read specs/CONSTITUTION.md, and replace the ${SLUG}-svc-example hexagon
and the bff's example/ app with your own domain. Everything else is scaffolding
you keep.
EOF
