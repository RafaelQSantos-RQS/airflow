.DEFAULT_GOAL := help

MAKEFLAGS += --no-print-directory

ifneq (,$(wildcard ./.env))
	include ./.env
	export
endif

COMPOSE_COMMAND                 = docker compose
COMPOSE_PROD_COMMAND            = docker compose -f docker-compose.yaml -f docker-compose.override.yaml -f docker-compose.prod.yaml --env-file .env

# --- Configuration Variables ---
ENV_FILE                        = .env
ENV_TEMPLATE                    = .env.template
ENV_PROD_TEMPLATE               = .env.prod.template

EXTERNAL_NETWORK_NAME           ?= web
POSTGRES_EXTERNAL_VOLUME_NAME   ?= airflow-database-volume

.PHONY: \
	help setup prune \
	up down rebuild build restart sync status logs pull validate \
	deploy pull-prod up-prod down-prod restart-prod validate-prod \
	_check-env-exists _create-env-from-template _create-network-if-not-exists _create-volume-if-not-exists

help: ## [GEN] 🤔 Show this help message
	@echo "\033[1;33mAvailable commands (general):\033[0m"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## \[GEN\]' $(MAKEFILE_LIST) \
	| sed -E 's/## \[GEN\] */## /' | sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

	@echo ""
	@echo "\033[1;33mAvailable commands (dev):\033[0m"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## \[DEV\]' $(MAKEFILE_LIST) \
	| sed -E 's/## \[DEV\] */## /' | sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

	@echo ""
	@echo "\033[1;33mAvailable commands (prod):\033[0m"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*?## \[PROD\]' $(MAKEFILE_LIST) \
	| sed -E 's/## \[PROD\] */## /' | sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## [GEN] 🛠️ Prepare the enviroment
	@echo "==> Preparing the environment..."
	@$(MAKE) _check-env-exists
	@$(MAKE) _init-env
	@$(MAKE) _create-network-if-not-exists
	@$(MAKE) _create-volume-if-not-exists
	@echo "The environment is ready. ☑️"

_check-env-exists:
	@if [ -f $(ENV_FILE) ]; then \
		echo "==> $(ENV_FILE) already exists"; \
		echo "==> Nothing will be done." ; \
	else \
		$(MAKE) _create-env-from-template; \
	fi

_create-env-from-template:
	@echo "==> $(ENV_FILE) not found. Creating from template..."
	@if [ ! -f $(ENV_TEMPLATE) ]; then \
		echo "❌ No $(ENV_TEMPLATE) found. Cannot continue."; \
		exit 1; \
	fi
	@cp $(ENV_TEMPLATE) $(ENV_FILE)
	@echo "⚠️ Please edit $(ENV_FILE) with your custom values."

_init-env:
	@echo "==> Configuring .env with dynamic values..."
	@echo "==> Setting AIRFLOW_UID to the current user's ID..."
	@UID=$$(id -u); \
		sed -i.bak "s|<USER_ID>|$$UID|g" $(ENV_FILE); 
	@echo "==> AIRFLOW_UID set to $$(id -u)"

	@echo "==> Generating a Fernet key using a temporary Airflow container"
	@FERNET_KEY=$$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"); \
		sed -i.bak "s|<FERNET_KEY>|'$$FERNET_KEY'|g" $(ENV_FILE); \
		echo "✅ Fernet key set in $(ENV_FILE)"
	@echo "==> AIRFLOW__CORE__FERNET_KEY generated"

	@echo "==> Clean up backup files created by sed"
	@rm -f $(ENV_FILE).bak
	@echo "==> .env configured successfully."

_create-network-if-not-exists:
	@echo "==> Checking for network $(EXTERNAL_NETWORK_NAME)..."
	@docker network inspect $(EXTERNAL_NETWORK_NAME) >/dev/null 2>&1 || \
		(echo "==> Network $(EXTERNAL_NETWORK_NAME) not found. Creating..." && docker network create $(EXTERNAL_NETWORK_NAME))
	@echo "✅ Network $(EXTERNAL_NETWORK_NAME) is ready."

_create-volume-if-not-exists:
	@echo "==> Checking for volume $(POSTGRES_EXTERNAL_VOLUME_NAME)..."
	@docker volume inspect $(POSTGRES_EXTERNAL_VOLUME_NAME) >/dev/null 2>&1 || \
		(echo "==> Volume $(POSTGRES_EXTERNAL_VOLUME_NAME) not found. Creating..." && docker volume create $(POSTGRES_EXTERNAL_VOLUME_NAME))
	@echo "✅ Volume $(POSTGRES_EXTERNAL_VOLUME_NAME) is ready."

sync: ## [GEN] ❗️ Sync with origin/main (discards local changes!)
	@read -p "⚠️ This will discard all local changes. Are you sure? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "==> Syncing with the remote repository (origin/main)..."; \
		git fetch origin; \
		git reset --hard origin/main; \
		echo "✅ Sync completed."; \
	else \
		echo "Sync cancelled."; \
	fi

# --- DEVELOPMENT TARGETS ---
up: ## [DEV] 🚀 Start containers (and build if necessary)
	@${COMPOSE_COMMAND} up -d --build --remove-orphans

down: ## [DEV] 🛑 Stop containers
	@${COMPOSE_COMMAND} down

restart: ## [DEV] 🔄 Restart running containers
	@${COMPOSE_COMMAND} restart

rebuild: down up ## [DEV] 💥 Rebuild images and restart all services
	@echo "✅ Rebuild complete."

build: ## [DEV] 🔨 Build or rebuild service images
	@${COMPOSE_COMMAND} build

status: ## [DEV] 📊 Show container status
	@${COMPOSE_COMMAND} ps

logs: ## [DEV] 📜 Show logs in real time
	@${COMPOSE_COMMAND} logs --follow

pull: ## [DEV] 📥 Pull images
	@${COMPOSE_COMMAND} pull

validate: ## [DEV] ✅ Validate the configuration file syntax.
	@${COMPOSE_COMMAND} config

# --- PRODUCTION TARGETS ---
deploy: up-prod prune ## [PROD] 🚀 Deploy the application to production
	@echo "✅ Deployment to production complete."

pull-prod: ## [PROD] 📥 Pull fresh images from the registry
	@echo "-> Pulling latest images for production..."
	@${COMPOSE_PROD_COMMAND} pull

up-prod: ## [PROD] 🚀 Start production services
	@echo "-> Starting production services..."
	@${COMPOSE_PROD_COMMAND} up -d --build --remove-orphans

down-prod: ## [PROD] 🛑 Stop production services
	@echo "-> Stopping production services..."
	@${COMPOSE_PROD_COMMAND} down -v
restart-prod: ## [PROD] 🔄 Restart production services
	@echo "-> Restarting production services..."
	@${COMPOSE_PROD_COMMAND} restart

validate-prod: ## [PROD] ✅ Validate the production configuration file syntax.
	@${COMPOSE_PROD_COMMAND} config

prune: ## [GEN] 🧹 Clean up unused Docker images
	@echo "-> Cleaning up unused Docker images..."
	@docker image prune -f

%: ## Generic target to catch unknown commands.
	@echo "🚫🚫 Error: Command not found. Please use 'make help' to see available commands."
