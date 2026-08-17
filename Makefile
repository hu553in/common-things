.DEFAULT_GOAL := check

PRETTIER := bunx prettier -u
ACTIONLINT := bunx github-actionlint
SHELLCHECK := bunx shellcheck
SHFMT := shfmt
SHELL_FILES := scripts/common_repos_config.sh scripts/common_repos_metadata.sh scripts/merge_prs_by_keyword.sh

.PHONY: lint
lint:
	$(PRETTIER) -c .
	$(SHFMT) -d $(SHELL_FILES)
	$(SHELLCHECK) $(SHELL_FILES)

.PHONY: lint-fix
lint-fix:
	$(PRETTIER) -w .
	$(SHFMT) -w $(SHELL_FILES)

.PHONY: check-config
check-config:
	git config --file .gitconfig --list >/dev/null
	scripts/common_repos_metadata.sh --validate-only
	bunx --package renovate renovate-config-validator --strict --no-global renovate.json presets/renovate/*.json
	$(ACTIONLINT)
	bash -n $(SHELL_FILES)

.PHONY: check
check: lint check-config

.PHONY: check-fix
check-fix: lint-fix
	$(MAKE) check
