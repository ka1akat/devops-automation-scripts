# Makefile — short commands for the blue-green deployment
# The pipeline uses the same targets, so manual and CI deploys share one logic.

STATE_DIR := /opt/bluegreen
PROXY_URL := http://localhost:8080

.DEFAULT_GOAL := help
.PHONY: help deploy rollback status

help:
	@echo "Available commands:"
	@echo "  make deploy IMAGE=<reference>  Deploy the specified image (blue-green)"
	@echo "  make rollback                  Restore the previous healthy release"
	@echo "  make status                    Show active color, image reference, app version and container status"
	@echo "  make help                      Describe available commands"

deploy:
	@if [ -z "$(IMAGE)" ]; then echo "ERROR: IMAGE is required. Usage: make deploy IMAGE=<reference>"; exit 2; fi
	@bash ./deploy.sh "$(IMAGE)"

rollback:
	@bash ./rollback.sh

status:
	@echo " ---Deployment state---  "
	@cat $(STATE_DIR)/state.env 2>/dev/null || echo "No deployment yet"
	@echo "Router points to: $$(grep -o 'api_[a-z]*' $(STATE_DIR)/traefik/routes.yml)"
	@echo
	@echo " ---Live check through the router---  "
	@curl -s --max-time 2 $(PROXY_URL)/health/live || echo "router not reachable"
	@echo
	@echo
	@echo " ---Containers--- "
	@docker ps -a --filter name=api_blue --filter name=api_green --filter name=bg_postgres --filter name=bg_router --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
