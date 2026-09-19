SHELL := /usr/bin/env bash

.PHONY: setup doctor start stop restart status logs health backup validate

setup:
	@test -n "$(DOMAIN)" || (echo "Usage: make setup DOMAIN=api.example.com"; exit 2)
	./scripts/setup.sh "$(DOMAIN)"

doctor:
	./scripts/doctor.sh

start:
	./scripts/start.sh

stop:
	docker compose --env-file .env down

restart:
	docker compose --env-file .env up -d --remove-orphans

status:
	docker compose --env-file .env ps

logs:
	docker compose --env-file .env logs --tail=200 -f

health:
	./scripts/healthcheck.sh

backup:
	./scripts/backup.sh

validate:
	./scripts/validate.sh
