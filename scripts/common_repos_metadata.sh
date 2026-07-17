#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
REPO_LIMIT="${REPO_LIMIT:-200}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
METADATA_FILE="${METADATA_FILE:-$REPO_ROOT/repos-metadata.json}"
apply=false
validate_only=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--apply | --validate-only]

Check GitHub repository metadata against $METADATA_FILE.
Use --apply to update descriptions, homepages, and topics.
Use --validate-only to check the local manifest without accessing GitHub.
EOF
}

github_api() {
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

repo_metadata() {
  local repo="$1"

  github_api "repos/$USER_OWNER/$repo" |
    jq -S -c '{
      description: (.description // ""),
      homepage: (if .homepage == "" then null else .homepage end),
      topics: ((.topics // []) | sort)
    }'
}

case "${1:-}" in
"") ;;
--apply) apply=true ;;
--validate-only) validate_only=true ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

if (($# > 1)); then
  usage >&2
  exit 2
fi

required_commands=(jq)
if [[ "$validate_only" == "false" ]]; then
  required_commands+=(gh)
fi

for command in "${required_commands[@]}"; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command" >&2
    exit 1
  fi
done

if ! jq -e '
  type == "object" and length > 0 and
  all(
    to_entries[];
    (.key | test("^[A-Za-z0-9._-]+$")) and
    (.value | type == "object") and
    (.value | keys == ["description", "homepage", "topics"]) and
    (
      .value.description |
      type == "string" and length > 0 and length <= 350 and (test("[.!?]$") | not)
    ) and
    (
      .value.homepage == null or
      (
        .value.homepage |
        type == "string" and test("^https://") and (endswith("/") | not)
      )
    ) and
    (
      .value.topics |
      type == "array" and length <= 20 and . == (sort | unique) and
      all(.[]; type == "string" and test("^[a-z0-9][a-z0-9-]{0,49}$"))
    )
  )
' "$METADATA_FILE" >/dev/null; then
  echo "Invalid repository metadata manifest: $METADATA_FILE" >&2
  exit 1
fi

if [[ "$validate_only" == "true" ]]; then
  echo "Repository metadata manifest is valid."
  exit 0
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

jq -r 'keys[]' "$METADATA_FILE" | LC_ALL=C sort >"$temporary_directory/manifest-repos"
gh repo list "$USER_OWNER" \
  --limit "$REPO_LIMIT" \
  --source \
  --json name \
  --jq '.[].name' |
  LC_ALL=C sort >"$temporary_directory/github-repos"

if ! cmp -s "$temporary_directory/manifest-repos" "$temporary_directory/github-repos"; then
  echo "Repository set differs from $METADATA_FILE:" >&2
  comm -23 "$temporary_directory/github-repos" "$temporary_directory/manifest-repos" |
    sed 's/^/  missing from manifest: /' >&2
  comm -13 "$temporary_directory/github-repos" "$temporary_directory/manifest-repos" |
    sed 's/^/  absent from GitHub: /' >&2
  exit 1
fi

drift=false
updated=0

while read -r repo; do
  expected="$(jq -S -c --arg repo "$repo" '.[$repo]' "$METADATA_FILE")"
  actual="$(repo_metadata "$repo")"

  if [[ "$actual" == "$expected" ]]; then
    continue
  fi

  if [[ "$apply" == "false" ]]; then
    drift=true
    echo "Metadata drift: $USER_OWNER/$repo" >&2
    jq -n --argjson expected "$expected" --argjson actual "$actual" \
      '{expected: $expected, actual: $actual}' >&2
    continue
  fi

  description="$(jq -r '.description' <<<"$expected")"
  homepage="$(jq -c '.homepage' <<<"$expected")"
  topics="$(jq -c '.topics' <<<"$expected")"

  jq -n \
    --arg description "$description" \
    --argjson homepage "$homepage" \
    '{description: $description, homepage: $homepage}' |
    github_api -X PATCH "repos/$USER_OWNER/$repo" --input - >/dev/null

  jq -n --argjson names "$topics" '{names: $names}' |
    github_api -X PUT "repos/$USER_OWNER/$repo/topics" --input - >/dev/null

  actual="$(repo_metadata "$repo")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Metadata still differs after update: $USER_OWNER/$repo" >&2
    exit 1
  fi

  updated=$((updated + 1))
  echo "Updated: $USER_OWNER/$repo"
done <"$temporary_directory/manifest-repos"

if [[ "$drift" == "true" ]]; then
  exit 1
fi

if [[ "$apply" == "true" ]]; then
  echo "Repository metadata is synchronized; updated $updated repositories."
else
  echo "Repository metadata matches $METADATA_FILE."
fi
