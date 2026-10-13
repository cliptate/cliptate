.DEFAULT_GOAL := help

PYTHON ?= python3
TAG ?= nightly
export TAG
export BUILD_VERSION
export ACT_SECRETS_FILE
export ACT_VARS_FILE

.PHONY: help resolve build test automation-test app run dmg ci package release actions-list actions-plan

help: ## Show task entry points
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

resolve: ## Resolve locked Swift packages
	swift package resolve --force-resolved-versions

build: ## Build the SwiftPM library
	swift build

test: ## Run SwiftPM tests
	swift test

automation-test: ## Test release automation without publishing
	$(PYTHON) -m unittest discover -s Tests/Automation -v

app: ## Build the Debug app with Xcode
	./scripts/build-and-run.sh build

run: ## Build and launch Cliptate Dev
	./scripts/run.sh

dmg: ## Build a local ad-hoc direct-download Release DMG
	CONFIGURATION=Release CLIPTATE_APP_STORE=NO ./scripts/build-and-run.sh build
	./scripts/package-dmg.sh

ci: ## Run the Test Action locally through act
	$(PYTHON) scripts/local-actions.py ci

package: ## Run signed packaging through act; keep dist/ (TAG=nightly or a version)
	$(PYTHON) scripts/local-actions.py package

release: ## Build, notarize, and publish through act (TAG=nightly or a pushed version)
	$(PYTHON) scripts/local-actions.py release

actions-list: ## List the CI and packaging jobs
	$(PYTHON) scripts/local-actions.py list

actions-plan: ## Inspect packaging stages through act without executing steps
	$(PYTHON) scripts/local-actions.py plan
