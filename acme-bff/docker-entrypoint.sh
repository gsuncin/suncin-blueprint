#!/usr/bin/env bash
# Wait for the database, then exec the real command.
#
# Deliberately does NOT run migrations. N containers starting at once would
# race for the migration lock, and the loser either blocks or fails; the deploy
# script runs them once, before any new container is swapped in.
set -euo pipefail

if [ "${SKIP_DB_WAIT:-0}" != "1" ]; then
    python - <<'PY'
import os
import sys
import time

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "core.settings")
django.setup()

from django.db import connections
from django.db.utils import OperationalError

timeout = int(os.environ.get("DB_WAIT_TIMEOUT", "60"))
interval = int(os.environ.get("DB_WAIT_INTERVAL", "2"))
deadline = time.monotonic() + timeout

while True:
    try:
        connections["default"].ensure_connection()
        break
    except OperationalError as exc:
        if time.monotonic() >= deadline:
            print(f"database not ready after {timeout}s: {exc}", file=sys.stderr)
            sys.exit(1)
        time.sleep(interval)
PY
fi

exec "$@"
