#!/usr/bin/env bash

set -euo pipefail

SECRET_NAME="GHCR_PAT"
SECRET_VALUE=""

for repo in $(gh repo list --limit 200 --source | awk '{print $1}'); do
  gh secret set "$SECRET_NAME" \
    --app dependabot \
    --repo "$repo" \
    --body "$SECRET_VALUE"
done
