# Common things

[![CI](https://github.com/hu553in/common-things/actions/workflows/ci.yml/badge.svg)](https://github.com/hu553in/common-things/actions/workflows/ci.yml)

Reusable GitHub Actions workflows and composite actions, Renovate presets, and maintenance scripts
for hu553in repositories.

## Reusable workflows and actions

Reusable workflows under `.github/workflows/` provide Bun, Python, Go, and Docker checks, Gradle
dependency submission, and Docker build, publish, and attestation jobs. Project CI workflows call
them directly from `main`.

Docker checks run Hadolint, BuildKit validation, an image build, and a blocking Trivy scan by
default. Publishing pushes the `sha-*` tag first and updates `latest` on the default branch only
after the scan passes, without rebuilding the image or replacing its digest.

Set `build: false` when a publishing job will build and scan the same image in that run; Hadolint
and BuildKit validation still run. Keep full image checks enabled on non-publishing refs.

Calling CI workflows group concurrent runs by workflow and ref, canceling superseded branch and
pull-request runs while letting tag releases finish. Keep concurrency in the caller so reusable
workflows do not cancel their parent run.

The Bun workflow's `cache_eslint` input enables the content-based ESLint cache. Its `playwright`
input enables browser caching, system dependencies, and test-result uploads on failure. The `shfmt`
input installs the shell formatter.

Custom workflows can reuse these composite actions after checkout:

- `hu553in/common-things/.github/actions/cache-eslint@main` caches `.cache/eslint`.
- `hu553in/common-things/.github/actions/scan-docker@main` accepts an `image-ref` and runs the same
  blocking Trivy scan against a local or published image, using the caller's Trivy configuration.
- `hu553in/common-things/.github/actions/setup-shfmt@main` installs shfmt after Go setup, using the
  caller's toolchain without changing it.

Use `build-publish-attest-docker.yml` when GitHub artifact attestations are available. Use the
lower-level Docker workflows for private repositories that cannot create attestations and for custom
release flows.

## Renovate presets

Target repositories extend the stack-specific presets under `presets/renovate/`:

```json
{
  "extends": ["github>hu553in/common-things//presets/renovate/bun"]
}
```

The `actions`, `bun`, `gradle`, `python`, and `go` presets enable only the managers relevant to each
stack. They share weekly scheduling, non-major grouping, assignment, labels, and GitHub Dependabot
alerts as the vulnerability source while Renovate creates remediation pull requests. Stack presets
coordinate runtime versions across project files and add language-specific grouping and lockfile
behavior.

## Repository maintenance

The shell helpers in `scripts/` manage GitHub state and require an authenticated `gh` CLI for live
checks and updates:

- `merge_prs_by_keyword.sh` searches and squash-merges open PRs by title keyword.
- `common_repos_config.sh` standardizes repository settings and protection rulesets.
- `common_repos_metadata.sh` checks repository descriptions, homepages, and topics against
  `repos-metadata.json`; pass `--validate-only` for an offline manifest check or `--apply` to update
  GitHub.

On public repositories, the GitHub user running the script can update, delete, and force-push
`main`; other users cannot.

Exact `vX.Y.Z` tags remain immutable. For `ascii-profile-card`, floating major tags such as `v1` and
`v2` are excluded from tag restrictions so its release workflow can move them to the latest
compatible releases.

```bash
REPOS="hu553in/common-things hu553in/personal-website" \
  KEYWORD="deps" \
  ./scripts/merge_prs_by_keyword.sh
REPOS="hu553in/common-things hu553in/personal-website" ./scripts/common_repos_config.sh
./scripts/common_repos_metadata.sh
./scripts/common_repos_metadata.sh --apply
```

Public-only or plan-gated operations are reported as skipped for private repositories.

## Local development

Local checks require Bun, jq, and shfmt. Git 2.54 or newer can use the tracked `.gitconfig` for
project checks and Commitlint hooks. Enable it once per clone:

```console
$ git config --local include.path ../.gitconfig
```

Run the complete local check or apply supported fixes before checking again:

```bash
make check
make check-fix
```
