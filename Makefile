SHELL := /bin/bash
STAGES := $(shell grep -vE '^\s*(\#|$$)' config/stages.txt)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

.PHONY: hooks
hooks: ## Install the mandatory pre-commit hooks (pre-commit and commit-msg)
	pre-commit install --install-hooks

.PHONY: check
check: ## Run every pre-commit hook on every file
	pre-commit run --all-files --show-diff-on-failure

.PHONY: fmt
fmt: ## terraform fmt, recursive
	terraform fmt -recursive

.PHONY: validate
validate: ## Validate every stage offline against a sibling checkout of gcp-terraform-module
	scripts/validate-local.sh $(MODULES)

.PHONY: docs
docs: ## Regenerate terraform-docs sections
	@for s in $(STAGES); do terraform-docs --config .terraform-docs.yml $$s; done

.PHONY: set-org
set-org: ## Replace the ORG placeholder: make set-org ORG=my-github-org
	scripts/set-org.sh $(ORG)

.PHONY: protect
protect: ## Apply branch ruleset and the production environment: make protect REPO=owner/repo TEAM=slug
	scripts/apply-branch-protection.sh $(REPO) $(TEAM)
