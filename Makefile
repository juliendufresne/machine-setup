# Optional, untracked overrides take precedence over the tracked defaults.
-include .env
-include .env.local

.DEFAULT_GOAL := help

# Name (tag) of the locally built dev toolbox image and the versions baked into
# it. Override any of these through .env / .env.local.
DEV_TOOL_IMAGE ?= machine-setup-dev-tools
SANDBOX_IMAGE ?= machine-setup-sandbox
UBUNTU_VERSION ?= 26.04
SHELLCHECK_VERSION ?= 0.11.0
SHELLSPEC_VERSION ?= 0.28.1

DEV_TOOL_CONTEXT := dev/docker/dev-tools
DEV_TOOL_DOCKERFILE := $(DEV_TOOL_CONTEXT)/Dockerfile
SANDBOX_CONTEXT := dev/docker/sandbox

# Pretty progress line.
log = printf '\033[1;34m▶ %s\033[0m\n' "$(1)"

# Every shell script under bin/, lib/, and libexec/, detected by its shebang so
# newly added scripts (including the extensionless helpers, the system-upgrade
# script, and the orchestrator) are linted automatically without editing this list.
SHELL_SCRIPTS := $(shell \
	find bin lib libexec -type f \
		-exec sh -c 'head -n1 "$$1" | grep -Eq "^#!.*\b(ba)?sh\b"' _ {} \; \
		-print 2>/dev/null)

# Base invocation of the dev toolbox: the container runs as the host user so
# nothing it writes is root-owned, and the working directory is the bind-mounted
# repository. The mount mode is supplied per target.
_DOCKER_BASE := docker run --rm \
	--workdir /work \
	--user "$(shell id -u):$(shell id -g)"

# Read-only mount: lint and test write only under the container's temp dir, so
# :ro is safe and keeps the host tree untouched.
_DOCKER_RUN := $(_DOCKER_BASE) --volume "$(CURDIR):/work:ro" $(DEV_TOOL_IMAGE)

# Read-write mount: coverage writes its report to var/coverage/ in the host tree.
_DOCKER_RUN_RW := $(_DOCKER_BASE) --volume "$(CURDIR):/work" $(DEV_TOOL_IMAGE)

# Sandbox invocation: a throwaway container that mirrors a real target host. The
# repo is mounted read-only (units read it; they never write it), so the only
# writable state is inside the container and vanishes with --rm. This is the one
# safe place to run a unit's real apt-get install/uninstall - never the host.
_SANDBOX_RUN := docker run --rm \
	--volume "$(CURDIR):/work:ro" \
	--workdir /work

# kcov options: shellspec's defaults (passing --kcov-options replaces them, so
# they are restated here) plus /dev/test/ so the spec files themselves are kept
# out of the coverage figures.
KCOV_OPTIONS := --include-path=. --include-pattern=.sh \
	--exclude-pattern=/.shellspec,/spec/,/coverage/,/report/,/dev/test/ \
	--path-strip-level=1

.PHONY: tools-build
tools-build: ## Build the dev toolbox image
	@$(call log,building $(DEV_TOOL_IMAGE))
	docker build \
		--tag $(DEV_TOOL_IMAGE) \
		--build-arg UBUNTU_VERSION=$(UBUNTU_VERSION) \
		--build-arg SHELLCHECK_VERSION=$(SHELLCHECK_VERSION) \
		--build-arg SHELLSPEC_VERSION=$(SHELLSPEC_VERSION) \
		$(DEV_TOOL_CONTEXT)

.PHONY: tools-ensure
tools-ensure: ## Build the dev toolbox image when it is missing
	@docker image inspect $(DEV_TOOL_IMAGE) >/dev/null 2>&1 \
		|| { printf 'Image %s not found - building...\n' "$(DEV_TOOL_IMAGE)"; \
			$(MAKE) --no-print-directory tools-build; }

.PHONY: tools-clean
tools-clean: ## Remove the dev toolbox image
	@$(call log,removing $(DEV_TOOL_IMAGE))
	-docker image rm $(DEV_TOOL_IMAGE)

.PHONY: sandbox-build
sandbox-build: ## Build the disposable sandbox image for running real units
	@$(call log,building $(SANDBOX_IMAGE))
	docker build \
		--tag $(SANDBOX_IMAGE) \
		--build-arg UBUNTU_VERSION=$(UBUNTU_VERSION) \
		--build-arg SANDBOX_UID=$(shell id -u) \
		--build-arg SANDBOX_GID=$(shell id -g) \
		$(SANDBOX_CONTEXT)

.PHONY: sandbox-ensure
sandbox-ensure: ## Build the sandbox image when it is missing
	@docker image inspect $(SANDBOX_IMAGE) >/dev/null 2>&1 \
		|| { printf 'Image %s not found - building...\n' "$(SANDBOX_IMAGE)"; \
			$(MAKE) --no-print-directory sandbox-build; }

.PHONY: sandbox-clean
sandbox-clean: ## Remove the sandbox image
	@$(call log,removing $(SANDBOX_IMAGE))
	-docker image rm $(SANDBOX_IMAGE)

.PHONY: sandbox
sandbox: sandbox-ensure ## Open a throwaway-host shell to run real units safely (your machine is untouched)
	@$(call log,sandbox shell ($(SANDBOX_IMAGE)) - exit discards it; your host is untouched)
	$(_SANDBOX_RUN) -it $(SANDBOX_IMAGE) bash

.PHONY: sandbox-run
sandbox-run: sandbox-ensure ## Run the orchestrator in the sandbox, e.g. make sandbox-run ARGS="install tmux"
	@$(call log,machine-setup $(ARGS) in $(SANDBOX_IMAGE))
	$(_SANDBOX_RUN) $(SANDBOX_IMAGE) bin/machine-setup $(ARGS)

.PHONY: lint
lint: lint-shell lint-github-workflows ## Run every linter (shell scripts + GitHub workflows)

.PHONY: lint-shell
lint-shell: tools-ensure ## Run shellcheck over every shell script under bin/, lib/, and libexec/
	@$(call log,shellcheck via $(DEV_TOOL_IMAGE))
	@if [ -z "$(strip $(SHELL_SCRIPTS))" ]; then \
		printf 'No shell scripts under bin/ lib/ libexec/ yet - skipping shellcheck.\n'; \
	else \
		$(_DOCKER_RUN) shellcheck --rcfile dev/.shellcheckrc $(SHELL_SCRIPTS); \
	fi

.PHONY: lint-github-workflows
lint-github-workflows: tools-ensure ## Lint workflow action format and shellcheck embedded scripts
	@$(call log,github workflow scan via $(DEV_TOOL_IMAGE))
	@if [ -z "$(wildcard .github/workflows/*.yml)" ]; then \
		printf 'No .github/workflows/*.yml yet - skipping workflow scan.\n'; \
	else \
		$(_DOCKER_RUN) python3 dev/bin/github_workflow_scan.py; \
	fi

.PHONY: test
test: tools-ensure ## Run the shellspec suite
	@$(call log,shellspec via $(DEV_TOOL_IMAGE))
	@if [ -z "$(wildcard .shellspec)" ]; then \
		printf 'No .shellspec configuration yet - skipping shellspec.\n'; \
	else \
		$(_DOCKER_RUN) shellspec; \
	fi

.PHONY: coverage
coverage: tools-ensure ## Run the suite under kcov, writing an HTML report to var/coverage/
	@$(call log,coverage via $(DEV_TOOL_IMAGE))
	@if [ -z "$(wildcard .shellspec)" ]; then \
		printf 'No .shellspec configuration yet - skipping coverage.\n'; \
	else \
		mkdir -p var/coverage; \
		$(_DOCKER_RUN_RW) shellspec --kcov --covdir var/coverage --kcov-options "$(KCOV_OPTIONS)"; \
		$(call log,report at var/coverage/index.html); \
	fi

.PHONY: fix-github-workflows
fix-github-workflows: tools-ensure ## Fix GitHub workflow action format in place
	@$(call log,fixing github workflow action format)
	$(_DOCKER_RUN_RW) python3 dev/bin/github_workflow_scan.py --fix-format

.PHONY: github-actions-outdated
github-actions-outdated: tools-ensure ## Report outdated GitHub actions (needs network)
	@$(call log,checking for outdated github actions)
	$(_DOCKER_RUN) python3 dev/bin/github_workflow_scan.py --report-outdated

.PHONY: github-actions-update
github-actions-update: tools-ensure ## Update GitHub actions to their latest version in place (needs network)
	@$(call log,updating github actions)
	$(_DOCKER_RUN_RW) python3 dev/bin/github_workflow_scan.py --update

.PHONY: check
check: lint test ## Run the linters and the test suite

.PHONY: help
help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*?## "}; \
		/^[a-zA-Z_-]+:.*?## / { printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
