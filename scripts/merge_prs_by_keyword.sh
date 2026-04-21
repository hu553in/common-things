#!/usr/bin/env bash

set -euo pipefail

OWNER="hu553in"
KEYWORD=""

echo "🔍 Searching for open PRs with '$KEYWORD' in title (user:$OWNER)..."

mapfile -t pr_urls < <(gh search prs \
  "$KEYWORD" \
  --state open \
  --owner "$OWNER" \
  --json url \
  --jq '.[].url' \
  --limit 100)

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
    echo "❌ Merge is failed."
  fi
done

echo "----------------------------------------"
echo "Done! Processed ${#pr_urls[@]} PR(s)."
