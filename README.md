# Common things

[![CI](https://github.com/hu553in/common-things/actions/workflows/ci.yml/badge.svg)](https://github.com/hu553in/common-things/actions/workflows/ci.yml)
[![Sync](https://github.com/hu553in/common-things/actions/workflows/sync.yml/badge.svg)](https://github.com/hu553in/common-things/actions/workflows/sync.yml)

Shared resources for cross-project use.

## Sync resources

- Root-level shared files are both the configs used by this repository and the canonical sync
  sources: `.editorconfig`, `.gitattributes`, `.gitconfig`, `.prettierrc.json`, `AGENTS.md`, and
  `CLAUDE.md`.
- `files/` contains static configs and workflow callers that are not used at the repository root.
- `templates/` contains repo-file-sync templates rendered with per-repository variables.
- `presets/renovate/` contains native Renovate presets referenced by target repositories.
- Source names identify the destination, optional variant, and template format, for example
  `dependabot.yml.njk`, `lefthook.bun.yml`, and `ci.yml.python`.

Current shared resources include agent instructions, base editor and Git configs, Dependabot
configs, Bun Lefthook and Release It! configs, formatter and hook configs, Go and Detekt lint
configs, static CI callers, and Renovate presets for Python and Go runtimes. Project-owned files
such as `.dockerignore` and `gradle.properties` remain local to each repository.

## Repo sync

`.github/sync.yml` is the source of truth for which repositories receive each file.

Sync only files that are intentionally identical in every listed repository. Keep files with
project-local sections under project ownership.

Keep static files that are not used by this repository under `files/`. Use `templates/` only when
the destination needs per-repository variables, such as enabled Dependabot ecosystems.

Target `renovate.json` files extend the presets under `presets/renovate/`. They cover only runtime
versions that Dependabot does not update; Dependabot continues to own package dependencies,
lockfiles, actions, and container images.

Reusable workflows under `.github/workflows/` provide shared Bun, Python, Go, and Docker image
checks, Gradle dependency submission, and Docker build/publish/attestation jobs. Docker checks run
Hadolint, BuildKit validation, an image build, and a blocking Trivy scan by default. The Bun
workflow can persist content-based ESLint and Playwright caches when callers enable the
`cache_eslint` and `cache_playwright` inputs.

Identical Bun, Python, Python with Docker, and Go with Docker CI callers are synced from
`files/workflows/`.

Use `build-publish-attest-docker.yml` for the standard Docker path and the lower-level Docker
workflows for custom release flows.

CI runs each project's non-mutating `check` command. Local prek hooks run `make check-fix`, while
Bun Lefthook hooks run `bun check:fix`, so formatter and linter fixes are applied before a commit.

Repositories without a hook manager receive `.gitconfig` with project-check and Commitlint hooks.
Bun and Git 2.54 or newer are required. Enable the tracked repository config once per clone:

```bash
git config --local include.path ../.gitconfig
```

Local checks also require uv, Golangci-lint, and shfmt.

## Scripts

The shell helpers in `scripts/` manage GitHub state. Live checks and updates expect an authenticated
`gh` CLI:

- `merge_prs_by_keyword.sh` searches and squash-merges open PRs by title keyword.
- `common_repos_config.sh` standardizes repository settings and protection rulesets.
- `common_repos_metadata.sh` checks repository descriptions, homepages, and topics against
  `repos-metadata.json`; pass `--validate-only` for an offline manifest check or `--apply` to update
  GitHub.

Exact `vX.Y.Z` tags remain immutable. For `ascii-profile-card`, floating major tags such as `v1` and
`v2` are excluded from tag restrictions so its release workflow can move them to the latest
compatible releases.

Configure scripts with environment variables:

```bash
REPOS="hu553in/common-things hu553in/personal-website" \
  KEYWORD="deps" \
  ./scripts/merge_prs_by_keyword.sh
REPOS="hu553in/common-things hu553in/personal-website" ./scripts/common_repos_config.sh
./scripts/common_repos_metadata.sh
./scripts/common_repos_metadata.sh --apply
```

Public-only or plan-gated operations are reported as skipped for private repositories.

## Checks

Run all formatter, shared-config, workflow, and shell checks before changing CI or scripts:

```bash
make check
make check-fix
```

Also compare synced files with sibling clones:

```bash
uv run --with pyyaml python scripts/check_shared_configs.py --repos-root ..
```
