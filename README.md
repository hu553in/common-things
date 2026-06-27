# Common things

Shared resources for cross-project use.

## Sync resources

- `files/` contains static files copied as-is.
- `templates/` contains repo-file-sync templates rendered with per-repository variables.
- Source names follow `<dest-file-name>[.<variant>][.njk]`, for example
  `.pre-commit-config.python.yaml.njk`, `.pre-commit-config.go.yaml`, and
  `.pre-commit-config.gradle.yaml`.

Current shared resources include common docs, base editor/git configs, Dependabot configs,
Python/Go/Gradle pre-commit configs, Go coverage config, Go lint config, and Detekt config.

## Repo sync

`.github/sync.yml` is the source of truth for which repositories receive each file.

Keep static files under `files/`. Use `templates/` only when the destination needs per-repository
variables, such as enabled Dependabot ecosystems or Go import prefixes.

## Scripts

Scripts in `scripts/` are manual GitHub maintenance helpers and expect an authenticated `gh` CLI:

- `set_dependabot_secret.sh` sets the Dependabot `GHCR_PAT` secret.
- `merge_prs_by_keyword.sh` searches and squash-merges open PRs by title keyword.
- `common_repos_config.sh` removes temporary repository rulesets by name.

Configure scripts with environment variables:

```bash
REPOS="hu553in/common-things hu553in/personal-website" SECRET_VALUE="..." ./scripts/set_dependabot_secret.sh
REPOS="hu553in/common-things hu553in/personal-website" KEYWORD="deps" ./scripts/merge_prs_by_keyword.sh
REPOS="hu553in/common-things hu553in/personal-website" ./scripts/common_repos_config.sh
```

Omit `REPOS` to process source repositories owned by `USER_OWNER` and joined organizations.

## Checks

Run shell checks before changing scripts:

```bash
bash -n scripts/*.sh
shellcheck scripts/*.sh
```
