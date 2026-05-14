#!/usr/bin/env bash

set -euo pipefail

SECRET_NAME="GHCR_PAT"
SECRET_VALUE=""

for owner in hu553in $(gh org list); do
  gh repo list "$owner" --limit 200 --source | awk '{print $1}'
done | while read -r repo; do
  gh secret set "$SECRET_NAME" \
    --app dependabot \
    --repo "$repo" \
    --body "$SECRET_VALUE"
done
