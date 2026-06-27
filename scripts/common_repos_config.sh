#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
REPO_LIMIT="${REPO_LIMIT:-200}"
REPOS="${REPOS:-}"

RULESET_NAMES=(
  "main: only me can update/delete"
  "main: no force pushes"
  "v*: only me can create"
  "v*: immutable once created"
)

step() {
  local name="$1"
  shift

  printf "  %-45s " "$name"

  if "$@" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "not ok"
  fi
}

ruleset_id() {
  local repo="$1"
  local name="$2"

  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/rulesets" \
    --jq ".[] | select(.name == \"$name\") | .id" | head -n 1
}

delete_ruleset_by_name() {
  local repo="$1"
  local name="$2"
  local id

  id="$(ruleset_id "$repo" "$name")"

  if [ -z "$id" ]; then
    return 0
  fi

  gh api \
    -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/rulesets/$id"
}

delete_all_temp_rulesets() {
  local repo="$1"

  for name in "${RULESET_NAMES[@]}"; do
    delete_ruleset_by_name "$repo" "$name"
  done
}

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
  echo
  echo "==> $repo"

  step "delete rulesets" \
    delete_all_temp_rulesets "$repo"
done
