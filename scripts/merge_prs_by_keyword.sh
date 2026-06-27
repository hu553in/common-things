#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
KEYWORD="${KEYWORD:-}"
REPOS="${REPOS:-}"

if [ -z "$KEYWORD" ]; then
  echo "KEYWORD is empty."
  exit 1
fi

pr_urls=()

repo_list_from_env() {
  printf '%s\n' "$REPOS" | tr ',' '\n' | tr '[:space:]' '\n' | sed '/^$/d'
}

if [ -n "$REPOS" ]; then
  mapfile -t repos < <(repo_list_from_env)
  echo "🔍 Searching for open PRs with '$KEYWORD' in title for repos: ${repos[*]}"

  for repo in "${repos[@]}"; do
    echo "→ Searching repo: $repo"

    mapfile -t repo_pr_urls < <(gh search prs \
      "$KEYWORD" \
      --state open \
      --match title \
      --repo "$repo" \
      --json url \
      --jq '.[].url' \
      --limit 100)

    pr_urls+=("${repo_pr_urls[@]}")
  done
else
  mapfile -t OWNERS < <(
    {
      echo "$USER_OWNER"
      gh org list
    } | sort -u
  )

  echo "🔍 Searching for open PRs with '$KEYWORD' in title for owners: ${OWNERS[*]}"

  for owner in "${OWNERS[@]}"; do
    echo "→ Searching owner: $owner"

    mapfile -t owner_pr_urls < <(gh search prs \
      "$KEYWORD" \
      --state open \
      --match title \
      --owner "$owner" \
      --json url \
      --jq '.[].url' \
      --limit 100)

    pr_urls+=("${owner_pr_urls[@]}")
  done
fi

if [[ ${#pr_urls[@]} -eq 0 ]]; then
  echo "No matching open PRs found."
  exit 0
fi

echo "Found ${#pr_urls[@]} PR(s) to process."

for url in "${pr_urls[@]}"; do
  echo "----------------------------------------"
  echo "URL: $url"
  echo "→ Merging with squashing and deleting branch..."

  if gh pr merge "$url" --squash --delete-branch; then
    echo "✅ Successfully merged!"
  else
    echo "❌ Merge failed."
  fi
done

echo "----------------------------------------"
echo "Done! Processed ${#pr_urls[@]} PR(s)."
