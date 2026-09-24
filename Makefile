# Thin wrappers. Everything here is a command you could type yourself; the
# Makefile exists so you do not have to remember which flags are load-bearing.

PROJECT      ?= acme
SCRATCH_DB   ?= acme_scratch
COMPOSE      := docker compose

# 5433 is the scratch Postgres from docker-compose.test.yml (`make test-db`),
# deliberately not 5432, so it cannot collide with a Postgres you already run --
# or, worse, with your own development data.
SCRATCH_ENV  := DEBUG=True \
	    DB_NAME=$(SCRATCH_DB) DB_USER=acme DB_PASSWORD=acme \
	    DB_HOST=127.0.0.1 DB_PORT=5433 CELERY_TASK_ALWAYS_EAGER=True

.DEFAULT_GOAL := help
.PHONY: help keys up down logs ps seed migrate shell test test-db test-db-reset \
	    test-db-down test-bff test-svc test-auth test-web test-tf verify fmt \
	    lint clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

keys: ## Generate the secrets that cannot be typed by hand, into .env
	@./scripts/gen-keys.sh

up: keys ## Build and start the whole stack
	$(COMPOSE) up -d --build --wait
	@$(MAKE) --no-print-directory migrate
	@$(MAKE) --no-print-directory seed
	@echo
	@echo "  app      http://app.localhost"
	@echo "  landing  http://acme.localhost"
	@echo "  sign in  dev@acme.test / acme-dev-password"

down: ## Stop the stack, keeping volumes
	$(COMPOSE) down

clean: ## Stop the stack and DELETE the data volumes
	$(COMPOSE) down -v

ps: ## Show container status and published ports
	$(COMPOSE) ps

logs: ## Follow logs (make logs S=bff)
	$(COMPOSE) logs -f $(S)

migrate: ## Run database migrations
	$(COMPOSE) exec -T bff python manage.py migrate --noinput
	$(COMPOSE) exec -T bff python manage.py createcachetable

seed: ## Create the local development account and user
	$(COMPOSE) exec -T bff python manage.py seed_dev

shell: ## Django shell inside the running bff
	$(COMPOSE) exec bff python manage.py shell

verify: ## Assert C-12: the gateway is the only ingress
	@./scripts/verify-isolation.sh

test: ## Run every suite, stopping at the first red (the C-8 exit gate)
	@DB_NAME=$(SCRATCH_DB) ./scripts/run-all-tests.sh

test-db: ## Start the scratch Postgres on 5433 and migrate it
# Separate from `up` on purpose: the application's Postgres publishes no port and
# lives on an internal network (C-12), and adding one there to make testing
# convenient would quietly undo that.
#
# Idempotent, and pinned to one compose project. Without `-p` the project name
# comes from the directory, so running this from a git worktree tries to create a
# SECOND scratch container and dies on the container name -- which is how you get
# "Conflict. The container name is already in use" for a database that is up and
# healthy and ready to be used.
	@docker inspect -f '{{.State.Running}}' $(PROJECT)-postgres-test 2>/dev/null | grep -qx true \
	  || $(COMPOSE) -p $(PROJECT)-test -f docker-compose.test.yml up -d --wait
	@cd acme-bff && $(SCRATCH_ENV) .venv/bin/python manage.py migrate --noinput
# The DRF throttle counters live in a database cache table. Without it a FRESH
# scratch database fails with 'relation "cache_table" does not exist' -- which
# passes on any machine where someone once ran this by hand, and fails in CI.
	@cd acme-bff && $(SCRATCH_ENV) .venv/bin/python manage.py createcachetable

test-db-reset: ## Drop and recreate the scratch database, then migrate it
# RUN THIS AFTER ANY BRANCH SWITCH THAT CROSSES A MIGRATION.
#
# `DATABASES["default"]["TEST"]["MIRROR"]` runs the suite against the scratch
# database DIRECTLY, so migrations applied on one branch are still applied after
# you switch to another -- and a branch that does not carry the migration file
# cannot unapply it, because Django has nothing to run backwards. The suite then
# fails with a not-null violation on code that is perfectly correct, which does
# not look like a database problem at all.
#
# Cheap because the volume is tmpfs: the data is disposable by design.
	@docker exec $(PROJECT)-postgres-test psql -U acme -d postgres \
	  -c "DROP DATABASE IF EXISTS $(SCRATCH_DB);" \
	  -c "CREATE DATABASE $(SCRATCH_DB) OWNER acme;" >/dev/null
	@cd acme-bff && $(SCRATCH_ENV) .venv/bin/python manage.py migrate --noinput
	@cd acme-bff && $(SCRATCH_ENV) .venv/bin/python manage.py createcachetable
	@echo "scratch database recreated and migrated"

test-db-down: ## Stop the scratch Postgres and delete its volume
	$(COMPOSE) -p $(PROJECT)-test -f docker-compose.test.yml down -v

test-bff: ## Django tests only (needs `make test-db` first)
# THE `cd` IS LOAD-BEARING. This target used to run
# `acme-bff/.venv/bin/python acme-bff/manage.py test` from the repo root, where
# Django's test runner discovers nothing and exits `Ran 0 tests ... OK` -- a
# green summary with nothing behind it. scripts/hooks/guard-bff-test-cwd.sh
# denies that spelling for the same reason.
	@cd acme-bff && $(SCRATCH_ENV) .venv/bin/python manage.py test

test-svc: ## Microservice tests only
# Derived AND cd'd. Hardcoding one service means the target reports success
# about a stack that has grown past it; running pytest from the repo root fails
# collection outright. A target advertised as "Microservice tests only" that
# tests no microservice is the worse of the two, because it is quiet.
	@set -e; found=0; \
	for dir in acme-svc-*/; do \
	  svc=$${dir%/}; \
	  [ -x "$$svc/.venv/bin/pytest" ] || { echo "SKIP $$svc (no .venv -- run its install first)"; continue; }; \
	  echo "--- $$svc"; ( cd "$$svc" && .venv/bin/pytest -q ); \
	  found=1; \
	done; \
	[ "$$found" = 1 ] || { echo "no microservice suite ran -- that is a failure, not a pass"; exit 1; }

test-auth: ## Gateway auth tests only
	@cd acme-gateway/auth && .venv/bin/pytest -q

test-web: ## Frontend unit and e2e tests only
	npm --prefix acme-web run test:unit
	npm --prefix acme-web run test:e2e

test-tf: ## Terraform format, validate and render tests
	terraform fmt -check -recursive acme-tf
	terraform -chdir=acme-tf/tests/render test

lint: ## Lint the frontend
	npm --prefix acme-web run lint

fmt: ## Format everything that has a formatter
	npm --prefix acme-web run format
	terraform fmt -recursive acme-tf
