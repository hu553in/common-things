from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "repos-metadata.json"
SYNC_PATH = ROOT / ".github/sync.yml"
YAML_CONFIGS = (ROOT / "files/configs/detekt.yml",)
SYNC_OWNER = "hu553in"
METADATA_ONLY_REPOS = {"dotfiles"}
REQUIRED_DESTINATIONS = {
    ".editorconfig",
    ".gitattributes",
    ".github/dependabot.yml",
    "AGENTS.md",
    "CLAUDE.md",
}
HOOK_DESTINATIONS = {".gitconfig", "lefthook.yml", "prek.toml"}
MANAGED_SOURCE_DIRS = (ROOT / "files", ROOT / "templates")
NUNJUCKS_RENDERER = """
const path = require("node:path");
const binDirectory = process.env.PATH.split(path.delimiter)[0];
const nunjucks = require(path.resolve(binDirectory, "../nunjucks"));
const input = JSON.parse(await Bun.stdin.text());

nunjucks.configure({ autoescape: true, trimBlocks: true, lstripBlocks: true });
process.stdout.write(nunjucks.render(input.path, input.context));
"""


def load_yaml(path: Path) -> Any:
    with path.open(encoding="utf-8") as file:
        return yaml.safe_load(file)


def validate_dependabot(rendered: str, source: Path) -> None:
    subprocess.run(
        [
            "uvx",
            "check-jsonschema",
            "--builtin-schema",
            "vendor.dependabot",
            "--force-filetype",
            "yaml",
            "--quiet",
            "/dev/stdin",
        ],
        cwd=ROOT,
        check=True,
        input=rendered,
        text=True,
    )

    config = yaml.safe_load(rendered)
    locations: set[tuple[str, tuple[str, ...]]] = set()
    for update in config["updates"]:
        directories = update.get("directories") or [update.get("directory")]
        location = (update["package-ecosystem"], tuple(directories))
        if location in locations:
            raise ValueError(f"{source}: duplicate rendered update {location}")
        locations.add(location)


def render_nunjucks(source: Path, context: dict[str, Any]) -> str:
    result = subprocess.run(
        [
            "bunx",
            "--package",
            "nunjucks",
            "bun",
            "-e",
            NUNJUCKS_RENDERER,
        ],
        cwd=ROOT,
        check=True,
        input=json.dumps(
            {
                "path": source.relative_to(ROOT).as_posix(),
                "context": context,
            }
        ),
        stdout=subprocess.PIPE,
        text=True,
    )
    return result.stdout


def target_path(repo: str, destination: str, repos_root: Path | None) -> Path | None:
    if repo == "hu553in/common-things":
        return ROOT / destination
    if repos_root is None:
        return None
    return repos_root / repo.rsplit("/", maxsplit=1)[-1] / destination


def validate_sync(repos_root: Path | None) -> None:
    config = load_yaml(SYNC_PATH)
    assignments: dict[tuple[str, str], str] = {}
    sync_repos: set[str] = set()
    sources: set[str] = set()

    for group in config["group"]:
        repos = [repo for repo in group["repos"].splitlines() if repo]
        if len(repos) != len(set(repos)):
            raise ValueError("duplicate repository in a sync group")
        sync_repos.update(repos)

        for file_config in group["files"]:
            source_name = file_config["source"]
            source = ROOT / source_name
            if not source.is_file():
                raise FileNotFoundError(source)
            sources.add(source_name)

            destination = file_config["dest"]
            if source.suffix == ".njk":
                expected = render_nunjucks(source, file_config.get("template", {}))
                if destination == ".github/dependabot.yml":
                    validate_dependabot(expected, source)
            else:
                expected = source.read_text(encoding="utf-8")

            for repo in repos:
                assignment = (repo, destination)
                if assignment in assignments:
                    raise ValueError(
                        f"{repo}:{destination} is assigned by both "
                        f"{assignments[assignment]} and {source_name}"
                    )
                assignments[assignment] = source_name

                target = target_path(repo, destination, repos_root)
                if target is None:
                    continue
                if not target.is_file():
                    raise FileNotFoundError(target)
                if target.read_text(encoding="utf-8") != expected:
                    raise ValueError(f"{target} differs from its sync source {source}")

    metadata_repos = set(json.loads(METADATA_PATH.read_text(encoding="utf-8")))
    unknown_metadata_only_repos = sorted(METADATA_ONLY_REPOS - metadata_repos)
    if unknown_metadata_only_repos:
        raise ValueError(
            "metadata-only repositories missing from repos-metadata.json: "
            + ", ".join(unknown_metadata_only_repos)
        )

    expected_sync_repos = {
        f"{SYNC_OWNER}/{repo}" for repo in metadata_repos - METADATA_ONLY_REPOS
    }
    unknown_repos = sorted(sync_repos - expected_sync_repos)
    if unknown_repos:
        raise ValueError(
            "sync repositories missing from repos-metadata.json: "
            + ", ".join(unknown_repos)
        )

    missing_repos = sorted(expected_sync_repos - sync_repos)
    if missing_repos:
        raise ValueError(
            "repositories missing from sync config: " + ", ".join(missing_repos)
        )

    missing_required_files = sorted(
        f"{repo}:{destination}"
        for repo in expected_sync_repos
        for destination in REQUIRED_DESTINATIONS
        if (repo, destination) not in assignments
    )
    if missing_required_files:
        raise ValueError(
            "repositories missing required sync files: "
            + ", ".join(missing_required_files)
        )

    invalid_hook_coverage = []
    for repo in sorted(expected_sync_repos):
        hooks = sorted(
            destination
            for destination in HOOK_DESTINATIONS
            if (repo, destination) in assignments
        )
        if len(hooks) != 1:
            invalid_hook_coverage.append(f"{repo}:{','.join(hooks) or 'none'}")
    if invalid_hook_coverage:
        raise ValueError(
            "repositories must receive exactly one hook config: "
            + ", ".join(invalid_hook_coverage)
        )

    managed_sources = {
        path.relative_to(ROOT).as_posix()
        for directory in MANAGED_SOURCE_DIRS
        for path in directory.rglob("*")
        if path.is_file()
    }
    orphaned_sources = sorted(managed_sources - sources)
    if orphaned_sources:
        raise ValueError(
            "sync sources without assignments: " + ", ".join(orphaned_sources)
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate shared configs and sync targets"
    )
    parser.add_argument(
        "--repos-root",
        type=Path,
        help="directory containing local clones named after their repositories",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repos_root = args.repos_root.resolve() if args.repos_root else None
    validate_sync(repos_root)
    for path in YAML_CONFIGS:
        load_yaml(path)

    subprocess.run(
        ["git", "config", "-f", "files/configs/.gitconfig", "--list"],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(
        ["uvx", "prek", "validate-config", "files/configs/prek.toml"],
        cwd=ROOT,
        check=True,
    )
    print("Shared configs are valid")


if __name__ == "__main__":
    main()
