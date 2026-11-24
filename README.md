# Common things

[![CI](https://github.com/hu553in/common-things/actions/workflows/ci.yml/badge.svg)](https://github.com/hu553in/common-things/actions/workflows/ci.yml)

Reusable GitHub Actions workflows, composite actions, and maintenance scripts for hu553in
repositories.

## Reusable workflows and actions

Reusable workflows under `.github/workflows/` provide Bun, Go, Python, Gradle, and Docker checks,
Gradle and Maven dependency submission, and Docker build, publish, and attestation jobs. Project CI
workflows call them directly from `main`. All of them accept `runs_on` to select a runner (default:
`ubuntu-latest`). Bun, Go, Python, and Gradle check steps receive `GITHUB_TOKEN` so tools that
download from GitHub are not rate limited.

The Docker check workflow (`check-docker.yml`) runs Hadolint, BuildKit validation, an image build,
and a blocking Trivy scan by default. The default branch and tags skip the build and scan because
publishing repeats them. Set `build_default_branch: true` for an image that is not published. Set
`build: false` when CI cannot build the image on any ref; Hadolint and BuildKit validation still
run.

The publish workflows (`build-publish-docker.yml`, `build-publish-attest-docker.yml`) require
`image`, a name without a tag, and output the pushed `digest`. They push the `sha-*` tag first and
update `latest` on the default branch only after the scan passes, without rebuilding the image or
replacing its digest.

The attest workflow (`attest-docker.yml`) requires `image` and `digest` and attests that digest.
`build-publish-attest-docker.yml` runs it after publishing.

SHA tags identify the source commit and may be replaced by rerunning a build. Pin the image digest
(`@sha256:...`) for an immutable deployment.

Set `context` (default: `.`) and `file` (default: `Dockerfile`) to choose what to build, and
`build_args` to pass newline-separated Docker build arguments (default: empty). Pass the same values
to both check and publish workflows.

Set `smoke_command` to check the image before scanning it (default: empty), for example
`/app/.venv/bin/python --version`. It runs with the image's default user through `/bin/sh -ec`, with
network access disabled. Pass the command to both check and publish workflows. The Docker check
workflow runs it whenever it builds the image; publish workflows run it against the built digest
before updating `latest`. Use a YAML anchor to keep both commands identical.

If the smoke command needs a seccomp profile, pass its relative path in the caller checkout as
`smoke_seccomp_profile` to both workflows. By default Docker uses its standard profile.

Set `no_cache_filters` to a comma-separated list of Docker stages to rebuild without cached layers
(default: empty). Use the runtime stage, such as `runner`, in both check and publish workflows to
fetch current OS package updates.

Calling CI workflows group concurrent runs by workflow and ref, canceling superseded branch and
pull-request runs while letting tag releases finish. Keep concurrency in the caller so reusable
workflows do not cancel their parent run.

The Bun workflow (`check-bun.yml`) runs the package script named by `check_script` (default:
`check:all`); a project can pass a narrower script, such as `check:static`, to keep slow suites out
of CI.

Set `playwright: true` to enable browser caching, system dependencies, and test-result uploads on
failure. Set `shfmt: true` to install the shell formatter. Set `node: true` when the project
declares a Node.js version in `package.json`; the workflow installs that version before running
checks. Set `node_options` to define `NODE_OPTIONS` for the check job (default: empty). For example,
`node_options: --max-old-space-size=4096` raises the Node.js old-space heap limit to 4 GiB.

The Go workflow (`check-go.yml`) verifies the golangci-lint configuration and runs
`make install-deps check`. It sets up uv when the checkout contains an `uv.lock` file.

The Python workflow (`check-python.yml`) runs `make install-deps` and `make check`. Run project
checks with `uv run --locked` so an outdated lockfile fails validation instead of being updated. Let
Ruff infer its target version from `project.requires-python`; an explicit `tool.ruff.target-version`
is unnecessary.

The Gradle workflow (`check-gradle.yml`) requires `java_version` and `gradle_jvmargs`, writes the
JVM arguments and `gradle_workers_max` (default: empty) to Gradle properties, and runs `make check`.
Gradle resolves dependencies itself, so it has no `make install-deps` step. Set `image_ref`
(default: empty) to also build that image with `bootBuildImage` and scan it. Set
`build_publish_refs: true` to include the default branch and tags, for example on a check-only
manual run. Test, coverage, and Detekt reports go to the `reports` artifact for 14 days.

The dependency submission workflows (`submit-gradle-dependencies.yml`,
`submit-maven-dependencies.yml`) require `java_version` and submit the dependency graph to GitHub.

Custom workflows can reuse these composite actions after checkout:

- `hu553in/common-things/.github/actions/release-notes@main` generates release notes with
  Conventional Changelog's `conventionalcommits` preset. Check out the release tag with
  `fetch-depth: 0`, then pass its `changelog` output to softprops' `body_path`. It includes breaking
  changes and ignores floating major tags. Additional aliases such as `vnext` or multiple release
  versions on one commit can make the upstream generator return empty notes; the action fails
  instead of publishing them.
- `hu553in/common-things/.github/actions/scan-docker@main` requires an `image-ref` and runs the same
  blocking Trivy scan against a local or published image, using the caller's Trivy configuration.
- `hu553in/common-things/.github/actions/setup-shfmt@main` installs the pinned shfmt release after
  Go setup, using the caller's toolchain.
- `hu553in/common-things/.github/actions/verify-docker@main` requires an `image-ref`, accepts a
  `smoke-command` (default: empty), runs the command in the image without network access, frees
  build cache, and runs `scan-docker`.

Use `build-publish-attest-docker.yml` when GitHub artifact attestations are available. Use
`build-publish-docker.yml` for private repositories that cannot create attestations, and
`attest-docker.yml` to attest an image published by a custom release flow.

## Repository maintenance

The shell helpers in `scripts/` manage GitHub state and require jq and an authenticated `gh` CLI for
live checks and updates:

- `common-repos-config.sh` standardizes repository settings and protection rulesets.
- `common-repos-metadata.sh` checks repository descriptions, homepages, and topics against
  `repos-metadata.json` and `reserve-repos.json`; pass `--validate-only` for an offline check of
  both files or `--apply` to update GitHub.

On public repositories, the GitHub user running the script can update, delete, and force-push
`main`; other users cannot.

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
```

Public-only or plan-gated operations are reported as skipped for private repositories. Archived
repositories are read-only: the config script applies immutable releases, GitHub Actions, workflow
permissions, and secret scanning to them and reports the other steps as skipped.

Reserve repositories are inactive backups listed in `reserve-repos.json` instead of
`repos-metadata.json`; their description, homepage, and topics stay empty. The config script
disables their issues, pull requests, dependency alerts (which also turns off Dependabot security
updates and, on private repositories, the dependency graph), and GitHub Actions, and leaves their
workflow permissions unchanged. On public reserve repositories it also disables private
vulnerability reporting. Other protections match active repositories.

Moving a repository from `reserve-repos.json` back to `repos-metadata.json` restores the active
settings on the next config script run.

## Local development

Local checks require Make, Bun, jq, and shfmt. Install the project-check and Commitlint hooks once
per clone:

```console
$ bunx lefthook install
```

Run the complete local check:

```bash
make check
```

Use `make check-fix` to apply supported fixes before the full check.

Focused checks:

```bash
make check-config
make check-workflows
```
