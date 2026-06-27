#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
REPO_LIMIT="${REPO_LIMIT:-200}"

SECRET_NAME="${SECRET_NAME:-GHCR_PAT}"
SECRET_VALUE="${SECRET_VALUE:-}"
REPOS="${REPOS:-}"

if [ -z "$SECRET_VALUE" ]; then
  echo "SECRET_VALUE is empty."
  exit 1
fi

repo_list_from_env() {
  printf '%s\n' "$REPOS" | tr ',' '\n' | tr '[:space:]' '\n' | sed '/^$/d'
}

if [ -n "$REPOS" ]; then
  repo_list_from_env
else
  for owner in "$USER_OWNER" $(gh org list); do
    gh repo list "$owner" --limit "$REPO_LIMIT" --source | awk '{print $1}'
  done
fi | while read -r repo; do
  echo "==> $repo"

  if gh secret set "$SECRET_NAME" \
    --app dependabot \
    --repo "$repo" \
    --body "$SECRET_VALUE" >/dev/null 2>&1; then
    echo "  secret                                      ok"
  else
    echo "  secret                                      not ok"
  fi
done
