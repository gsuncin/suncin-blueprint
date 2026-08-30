# Thin wrappers. Everything here is a command you could type yourself; the
# Makefile exists so you do not have to remember which flags are load-bearing.

PROJECT      ?= acme
SCRATCH_DB   ?= acme_scratch
COMPOSE      := docker compose

.DEFAULT_GOAL := help
.PHONY: help keys up down logs ps seed migrate shell test test-bff test-svc \
	    test-auth test-web test-tf verify fmt lint clean

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

test-bff: ## Django tests only
	@DEBUG=True DB_NAME=$(SCRATCH_DB) acme-bff/.venv/bin/python acme-bff/manage.py test

test-svc: ## Microservice tests only
	@acme-svc-example/.venv/bin/pytest -q

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
