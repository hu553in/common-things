#!/usr/bin/env bash

set -euo pipefail

for owner in hu553in $(gh org list); do
  gh repo list "$owner" --limit 200 --source | awk '{print $1}'
done | while read -r repo; do
  gh repo edit "$repo" \
    --delete-branch-on-merge \
    --allow-update-branch \
    --enable-merge-commit=false \
    --enable-projects=false \
    --enable-discussions=false \
    --enable-rebase-merge=false \
    --enable-secret-scanning \
    --enable-secret-scanning-push-protection \
    --enable-squash-merge \
    --enable-wiki=false ||
    gh repo edit "$repo" \
      --delete-branch-on-merge \
      --allow-update-branch \
      --enable-merge-commit=false \
      --enable-projects=false \
      --enable-discussions=false \
      --enable-rebase-merge=false \
      --enable-squash-merge \
      --enable-wiki=false
done
