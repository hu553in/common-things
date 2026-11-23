.DEFAULT_GOAL := check

PREK ?= prek
ACTIONLINT := bunx --minimum-release-age 259200 github-actionlint
SHELLCHECK := bunx --minimum-release-age 259200 shellcheck
SHFMT := shfmt
SHELL_FILES := scripts/common-repos-config.sh scripts/common-repos-metadata.sh

.PHONY: lint
lint:
	bun fmt --check
	$(SHFMT) -d $(SHELL_FILES)
	$(SHELLCHECK) $(SHELL_FILES)

.PHONY: lint-fix
lint-fix:
	bun fmt
	$(SHFMT) -w $(SHELL_FILES)

.PHONY: check-config
check-config:
	$(PREK) validate-config prek.toml
	scripts/common-repos-metadata.sh --validate-only

.PHONY: check-workflows
check-workflows:
	$(ACTIONLINT)
	printf '%s\0' .github/actions/*/action.yml | xargs -0 -n 1 bunx --minimum-release-age 259200 --package @action-validator/cli action-validator

.PHONY: check
check: lint check-config check-workflows

.PHONY: check-fix
check-fix: lint-fix
	$(MAKE) check
