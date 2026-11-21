# Cibles communes à tous les dépôts : test, build, deploy, logs.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
APP := $(shell sed -n 's/^name: *//p' platform.yaml)
TIER ?= staging
NS = $(if $(filter preview,$(TIER)),app-$(APP)-pr-$(PR),app-$(APP)-$(TIER))
KUBECONFIG_AGENT ?= $(HOME)/.kube/agent-reader.yaml

.PHONY: help setup test lint unit guard modules validate scan build run deploy logs status clean

help: ## Affiche cette aide
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

setup: ## Installe l'environnement Python figé (uv)
	uv sync --frozen

test: lint unit guard validate scan ## Tous les contrôles (identiques à la CI)

lint: ## ruff (lint + format)
	uv run --frozen ruff check .
	uv run --frozen ruff format --check .

unit: ## Tests unitaires
	uv run --frozen pytest -q

guard: ## Garde-fou des migrations destructives (par rapport à origin/main)
	@if git rev-parse --verify -q origin/main >/dev/null; then uv run --frozen python scripts/migration-guard.py --base origin/main; \
	else uv run --frozen python scripts/migration-guard.py migrations/*.sql; fi

modules: ## Applique platform.yaml aux composants de deploy/
	uv run --frozen python scripts/modules.py

validate: ## Rend deploy/ (3 niveaux × 3 configurations), kubeconform, règles d'admission
	scripts/validate-deploy.sh

scan: ## Gitleaks, Semgrep, Trivy (fichiers)
	gitleaks dir . --no-banner --redact
	semgrep scan --config p/default --config p/python --error --quiet --metrics=off --exclude out --exclude .venv
	trivy fs --quiet --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
	  --skip-dirs out --skip-dirs .venv .

build: ## Construit l'image locale (sans la publier)
	docker build -t $(APP):dev $(if $(filter static,$(shell sed -n 's/^kind: *//p' platform.yaml)),-f Dockerfile.static,) .

run: ## Lance l'application en local (http://localhost:8080)
	uv run --frozen uvicorn app.main:app --reload --port 8080

deploy: ## [CI/HUMAIN] Publie image + artefact deploy/ (TAG=pr-<n>|main|X.Y.Z). La plateforme déploie.
	TAG=$(TAG) scripts/publish.sh

logs: ## Journaux du niveau TIER (staging par défaut ; preview : PR=<n>), en lecture seule
	KUBECONFIG=$(KUBECONFIG_AGENT) kubectl logs -n $(NS) -l app.kubernetes.io/name=$(APP) --all-containers --prefix --tail=200

status: ## État Flux et pods du niveau TIER, en lecture seule
	KUBECONFIG=$(KUBECONFIG_AGENT) kubectl get kustomization,ocirepository -n flux-system | grep -E "NAME|$(NS)" || true
	KUBECONFIG=$(KUBECONFIG_AGENT) kubectl get pods,ingress,clusters.postgresql.cnpg.io -n $(NS)

clean: ## Supprime les sorties locales
	find out -mindepth 1 -delete 2>/dev/null || true
