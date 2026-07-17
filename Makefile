.DEFAULT_GOAL := check

PRETTIER := bunx prettier -u
ACTIONLINT := bunx github-actionlint
SHELLCHECK := bunx shellcheck
SHFMT := shfmt
RUFF := uvx ruff
TAPLO := bunx @taplo/cli
SHELL_FILES := scripts/common_repos_config.sh scripts/common_repos_metadata.sh scripts/merge_prs_by_keyword.sh
PYTHON_FILES := scripts/check_shared_configs.py

.PHONY: lint
lint:
	$(PRETTIER) -c .
	$(SHFMT) -d $(SHELL_FILES)
	$(SHELLCHECK) $(SHELL_FILES)
	$(RUFF) check $(PYTHON_FILES)
	$(RUFF) format --check $(PYTHON_FILES)
	$(TAPLO) fmt --check

.PHONY: lint-fix
lint-fix:
	$(PRETTIER) -w .
	$(SHFMT) -w $(SHELL_FILES)
	$(RUFF) check --fix $(PYTHON_FILES)
	$(RUFF) format $(PYTHON_FILES)
	$(TAPLO) fmt

.PHONY: check-config
check-config:
	uv run --with pyyaml python scripts/check_shared_configs.py
	scripts/common_repos_metadata.sh --validate-only
	bunx --package renovate renovate-config-validator --strict --no-global files/configs/renovate.python.json files/configs/renovate.go.json
	LEFTHOOK_CONFIG=files/configs/lefthook.bun.yml bunx lefthook validate
	golangci-lint config verify -c files/configs/.golangci.yaml
	$(ACTIONLINT)
	$(ACTIONLINT) files/workflows/ci.yml.*
	bash -n $(SHELL_FILES)

.PHONY: check
check: lint check-config

.PHONY: check-fix
check-fix: lint-fix
	$(MAKE) check
