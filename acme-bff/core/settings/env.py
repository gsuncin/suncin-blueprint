"""Environment loading, pinned to this project's own .env.

python-decouple's default `AutoConfig` walks **up** the directory tree looking
for a `.env` or `settings.ini`. In a monorepo that is not hypothetical: the
repo-root `.env` that configures `docker compose` was being read by
`manage.py test` from this directory, so whether a test passed depended on
whether someone had run `make keys` — a file that is gitignored and therefore
different on every machine and absent in CI.

That is the same failure mode the FastAPI services avoid with
`Settings(_env_file=None)` in their fixtures. Here the fix is to pin the search
to exactly one path and never look at a parent.

Environment variables still win over the file, which is what makes the
container case work: compose passes the root `.env` in as real environment
variables, and this module never sees it as a file at all.
"""

from pathlib import Path

from decouple import Config, RepositoryEmpty, RepositoryEnv

BASE_DIR = Path(__file__).resolve().parent.parent.parent

_env_file = BASE_DIR / ".env"

config = (
    Config(RepositoryEnv(str(_env_file)))
    if _env_file.is_file()
    else Config(RepositoryEmpty())
)
