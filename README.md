# Common things

[![CI](https://github.com/hu553in/common-things/actions/workflows/ci.yml/badge.svg)](https://github.com/hu553in/common-things/actions/workflows/ci.yml)

Reusable GitHub Actions workflows and composite actions, Renovate presets, and maintenance scripts
for hu553in repositories.

## Reusable workflows and actions

Reusable workflows under `.github/workflows/` provide Bun, Go, Python, and Docker checks, Gradle and
Maven dependency submission, and Docker build, publish, and attestation jobs. Project CI workflows
call them directly from `main`.

Docker checks run Hadolint, BuildKit validation, an image build, and a blocking Trivy scan by
default. Publishing pushes the `sha-*` tag first and updates `latest` on the default branch only
after the scan passes, without rebuilding the image or replacing its digest.

SHA tags identify the source commit and may be replaced by rerunning a build. Pin the image digest
(`@sha256:...`) for an immutable deployment.

Set `build: false` when a publishing job will build and check the image in that run; Hadolint and
BuildKit validation still run. Keep full image checks enabled on non-publishing refs.

Set `smoke_command` to check the image before scanning it, for example
`/app/.venv/bin/python --version`. It runs with the image's default user through `/bin/sh -ec`, with
network access disabled. Pass the command to both check and publish workflows. The check workflow
runs it when `build` is enabled; publishing workflows run it against the built digest before
updating `latest`. Use a YAML anchor to keep both commands identical.

Set `no_cache_filters` to a comma-separated list of Docker stages to rebuild without cached layers
(default: empty). Use the runtime stage, such as `runner`, in both check and publish jobs to fetch
current OS package updates.

Calling CI workflows group concurrent runs by workflow and ref, canceling superseded branch and
pull-request runs while letting tag releases finish. Keep concurrency in the caller so reusable
workflows do not cancel their parent run.

The Bun workflow runs the package script named by `check_script` (default: `check`); a project can
pass a narrower script, such as `check:static`, to keep slow suites out of CI. Its `cache_eslint`
input restores and saves `.cache/eslint`. Enable caching in the project's ESLint command with
`--cache --cache-strategy content --cache-location .cache/eslint`. The `playwright` input enables
browser caching, system dependencies, and test-result uploads on failure. The `shfmt` input installs
the shell formatter. Set `node: true` when the project declares a Node.js version in `package.json`;
the workflow installs that version before running checks. The `node_options` input sets
`NODE_OPTIONS` for the check job and defaults to an empty string. For example,
`node_options: --max-old-space-size=4096` raises the Node.js old-space heap limit to 4 GiB.

The Python workflow runs `make install-deps` and `make check`. Run project checks with
`uv run --locked` so an outdated lockfile fails validation instead of being updated. Let Ruff infer
its target version from `project.requires-python`; an explicit `tool.ruff.target-version` is
unnecessary.

Custom workflows can reuse these composite actions after checkout:

- `hu553in/common-things/.github/actions/cache-eslint@main` caches `.cache/eslint`.
- `hu553in/common-things/.github/actions/release-notes@main` generates release notes with
  Conventional Changelog's `conventionalcommits` preset. Check out the release tag with
  `fetch-depth: 0`, then pass its `changelog` output to softprops' `body_path`. It includes breaking
  changes and ignores floating major tags. Additional aliases such as `vnext` or multiple release
  versions on one commit can make the upstream generator return empty notes; the action fails
  instead of publishing them.
- `hu553in/common-things/.github/actions/scan-docker@main` accepts an `image-ref` and runs the same
  blocking Trivy scan against a local or published image, using the caller's Trivy configuration.
- `hu553in/common-things/.github/actions/setup-shfmt@main` installs shfmt after Go setup, using the
  caller's toolchain without changing it.

Use `build-publish-attest-docker.yml` when GitHub artifact attestations are available. Use the
lower-level Docker workflows for private repositories that cannot create attestations and for custom
release flows.

The publishing workflows accept `runs_on` to select a runner (default: `ubuntu-latest`).

## Renovate presets

Target repositories extend the stack-specific presets under `presets/renovate/`:

```json
{
  "extends": ["github>hu553in/common-things//presets/renovate/bun"]
}
```

The `actions`, `bun`, `go`, `gradle`, `maven`, and `python` presets enable only the managers
relevant to each stack. Dependency updates can create PRs at any time, whenever Renovate runs.
Lockfile maintenance can create PRs throughout Monday in UTC. The presets share non-major grouping,
assignment, labels, and GitHub Dependabot alerts as the vulnerability source while Renovate creates
remediation pull requests. Stack presets coordinate runtime versions across project files and add
language-specific grouping and lockfile behavior.

Renovate merges its PRs once CI checks pass and the branch is up to date. PRs without CI checks stay
open. GitHub's native auto-merge stays disabled.

Python-tagged uv images follow Python versions, while numeric uv image tags follow uv releases.

The Gradle preset also tracks annotated Spring dependency overrides and Docker buildpacks:

- In `gradle.properties`, put `# renovate: datasource=maven depName=<group>:<artifact>` immediately
  before the version property, using the dependency's Maven coordinates.
- In `build.gradle.kts`, put `// renovate: datasource=docker` immediately before the quoted
  buildpack image and tag.

## Repository maintenance

The shell helpers in `scripts/` manage GitHub state and require an authenticated `gh` CLI for live
checks and updates:

- `common-repos-config.sh` standardizes repository settings and protection rulesets.
- `common-repos-metadata.sh` checks repository descriptions, homepages, and topics against
  `repos-metadata.json`; pass `--validate-only` for an offline manifest check or `--apply` to update
  GitHub.
- `merge-prs-by-keyword.sh` searches and squash-merges open PRs by title keyword.

On public repositories, the GitHub user running the script can update, delete, and force-push
`main`; other users cannot. The Renovate GitHub App can also merge pull requests into `main`.

The script sets default `GITHUB_TOKEN` permissions to `read`; jobs can request additional
permissions. **Allow GitHub Actions to create and approve pull requests** is enabled for
`homebrew-tap` and disabled for other repositories.

Exact `vX.Y.Z` tags remain immutable. For `ascii-profile-card`, floating major tags such as `v1` and
`v2` are excluded from tag restrictions so its release workflow can move them to the latest
compatible releases.

```bash
REPOS="hu553in/common-things hu553in/personal-website" ./scripts/common-repos-config.sh
./scripts/common-repos-metadata.sh
./scripts/common-repos-metadata.sh --apply
REPOS="hu553in/common-things hu553in/personal-website" \
  KEYWORD="deps" \
  ./scripts/merge-prs-by-keyword.sh
```

Public-only or plan-gated operations are reported as skipped for private repositories.

## Local development

Local checks require Make, Bun, Node.js, jq, and shfmt. Git 2.54 or newer can use the tracked
`.gitconfig` for project checks and Commitlint hooks. Enable it once per clone:

```console
$ git config --local include.path ../.gitconfig
```

Run the complete local check or apply supported fixes before checking again:

```bash
make check
make check-fix
```

Focused checks:

```bash
make check-config
make check-renovate
make check-workflows
```
