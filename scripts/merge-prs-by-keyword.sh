#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
KEYWORD="${KEYWORD:-}"
REPOS="${REPOS:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESERVE_FILE="${RESERVE_FILE:-$SCRIPT_DIR/../reserve-repos.json}"

if [ -z "$KEYWORD" ]; then
  echo "KEYWORD is empty."
  exit 1
fi

pr_urls=()
failed=false

repo_list_from_env() {
  printf '%s\n' "$REPOS" | tr ',' '\n' | tr '[:space:]' '\n' | sed '/^$/d'
}

if [ -n "$REPOS" ]; then
  repos=()
  repo_list="$(repo_list_from_env)"
  while read -r repo; do
    [[ -n "$repo" ]] && repos+=("$repo")
  done <<<"$repo_list"

  echo "🔍 Searching for open PRs with '$KEYWORD' in title for repos: ${repos[*]}"

  for repo in "${repos[@]}"; do
    echo "→ Searching repo: $repo"

    repo_pr_urls="$(gh search prs \
      "$KEYWORD" \
      --state open \
      --match title \
      --repo "$repo" \
      --json url \
      --jq '.[].url' \
      --limit 100)"

    while read -r url; do
      [[ -n "$url" ]] && pr_urls+=("$url")
    done <<<"$repo_pr_urls"
  done
else
  echo "🔍 Searching for open PRs with '$KEYWORD' in title for owner: $USER_OWNER"

  owner_pr_urls="$(gh search prs \
    "$KEYWORD" \
    --state open \
    --match title \
    --owner "$USER_OWNER" \
    --json url \
    --jq '.[].url' \
    --limit 100)"

  while read -r url; do
    [[ -n "$url" ]] && pr_urls+=("$url")
  done <<<"$owner_pr_urls"
fi

if [[ ${#pr_urls[@]} -eq 0 ]]; then
  echo "No matching open PRs found."
  exit 0
fi

reserve_repos="$(jq -r '.[]' "$RESERVE_FILE")"
active_pr_urls=()
for url in "${pr_urls[@]}"; do
  repo_path="${url#https://github.com/}"
  repo_path="${repo_path%%/pull/*}"
  if [[ "${repo_path%%/*}" == "$USER_OWNER" ]] && grep -Fxq -- "${repo_path#*/}" <<<"$reserve_repos"; then
    echo "Skipping reserve repository PR: $url"
  else
    active_pr_urls+=("$url")
  fi
done

if [[ ${#active_pr_urls[@]} -eq 0 ]]; then
  echo "No matching open PRs outside reserve repositories."
  exit 0
fi
pr_urls=("${active_pr_urls[@]}")

echo "Found ${#pr_urls[@]} PR(s) to process."

for url in "${pr_urls[@]}"; do
  echo "----------------------------------------"
  echo "URL: $url"
  echo "→ Merging with squashing and deleting branch..."

  if gh pr merge "$url" --squash --delete-branch; then
    echo "✅ Successfully merged!"
  else
    echo "❌ Merge failed."
    failed=true
  fi
done

echo "----------------------------------------"
echo "Done! Processed ${#pr_urls[@]} PR(s)."

if [[ "$failed" == "true" ]]; then
  exit 1
fi
