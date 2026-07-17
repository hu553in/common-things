#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
REPO_LIMIT="${REPO_LIMIT:-200}"
REPOS="${REPOS:-}"
failed=false

step() {
  local name="$1"
  local output
  shift

  printf "  %-45s " "$name"

  if output="$("$@" 2>&1)"; then
    echo "ok"
  else
    echo "not ok"
    if [[ -n "$output" ]]; then
      printf '    %s\n' "${output//$'\n'/$'\n    '}" >&2
    fi
    failed=true
  fi
}

skip() {
  local name="$1"
  local reason="$2"

  printf "  %-45s skipped (%s)\n" "$name" "$reason"
}

edit_repo() {
  local repo="$1"

  gh repo edit "$repo" \
    --default-branch main \
    --delete-branch-on-merge \
    --allow-update-branch \
    --enable-auto-merge=false \
    --enable-issues \
    --enable-merge-commit=false \
    --enable-projects=false \
    --enable-discussions=false \
    --enable-rebase-merge=false \
    --enable-squash-merge \
    --enable-wiki=false
}

enable_secret_scanning() {
  local repo="$1"

  gh repo edit "$repo" \
    --enable-secret-scanning \
    --enable-secret-scanning-push-protection
}

github_api() {
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

ruleset_id() {
  local repo="$1"
  local name="$2"
  local target="$3"

  github_api \
    "repos/$repo/rulesets?targets=$target" \
    --jq "map(select(.name == \"$name\")) | .[0].id // \"\""
}

put_ruleset() {
  local repo="$1"
  local name="$2"
  local target="$3"
  local body="$4"
  local id

  if ! id="$(ruleset_id "$repo" "$name" "$target")"; then
    return 1
  fi

  if [ -n "$id" ]; then
    printf '%s' "$body" | github_api \
      -X PUT \
      "repos/$repo/rulesets/$id" \
      --input -
  else
    printf '%s' "$body" | github_api \
      -X POST \
      "repos/$repo/rulesets" \
      --input -
  fi
}

repo_list_from_env() {
  printf '%s\n' "$REPOS" | tr ',' '\n' | tr '[:space:]' '\n' | sed '/^$/d'
}

repo_list() {
  if [ -n "$REPOS" ]; then
    repo_list_from_env
    return
  fi

  gh repo list "$USER_OWNER" \
    --limit "$REPO_LIMIT" \
    --source \
    --json nameWithOwner \
    --jq '.[].nameWithOwner'
}

protect_main_only_me() {
  local repo="$1"
  local user_id="$2"

  put_ruleset "$repo" "main: only me can update/delete" "branch" "$(
    cat <<EOF
{
  "name": "main: only me can update/delete",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": $user_id,
      "actor_type": "User",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "update",
      "parameters": {
        "update_allows_fetch_and_merge": true
      }
    },
    {
      "type": "deletion"
    }
  ]
}
EOF
  )"
}

protect_main_no_force_push() {
  local repo="$1"

  put_ruleset "$repo" "main: no force pushes" "branch" "$(
    cat <<EOF
{
  "name": "main: no force pushes",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "non_fast_forward"
    }
  ]
}
EOF
  )"
}

protect_v_tags_only_me_create() {
  local repo="$1"
  local user_id="$2"

  put_ruleset "$repo" "v*: only me can create" "tag" "$(
    cat <<EOF
{
  "name": "v*: only me can create",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [
    {
      "actor_id": $user_id,
      "actor_type": "User",
      "bypass_mode": "always"
    }
  ],
  "conditions": {
    "ref_name": {
      "include": ["refs/tags/v*"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "creation"
    }
  ]
}
EOF
  )"
}

protect_v_tags_immutable() {
  local repo="$1"

  put_ruleset "$repo" "v*: immutable once created" "tag" "$(
    cat <<EOF
{
  "name": "v*: immutable once created",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/tags/v*"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "update",
      "parameters": {
        "update_allows_fetch_and_merge": false
      }
    },
    {
      "type": "deletion"
    },
    {
      "type": "non_fast_forward"
    }
  ]
}
EOF
  )"
}

user_id="$(github_api user --jq .id)"

repos="$(repo_list)"

while read -r repo; do
  [[ -z "$repo" ]] && continue

  visibility="$(github_api "repos/$repo" --jq .visibility)"

  echo
  echo "==> $repo"

  step "repo settings" \
    edit_repo "$repo"

  step "immutable releases" \
    github_api \
    -X PUT \
    "repos/$repo/immutable-releases"

  step "workflow permissions" \
    github_api \
    -X PUT \
    "repos/$repo/actions/permissions/workflow" \
    -F "default_workflow_permissions=read" \
    -F "can_approve_pull_request_reviews=false"

  step "dependency graph + alerts" \
    github_api \
    -X PUT \
    "repos/$repo/vulnerability-alerts"

  step "dependabot security updates" \
    github_api \
    -X PUT \
    "repos/$repo/automated-security-fixes"

  if [[ "$visibility" == "public" ]]; then
    step "private vulnerability reporting" \
      github_api \
      -X PUT \
      "repos/$repo/private-vulnerability-reporting"

    step "secret scanning + push protection" \
      enable_secret_scanning "$repo"

    step "protect main: only me" \
      protect_main_only_me "$repo" "$user_id"

    step "protect main: no force push" \
      protect_main_no_force_push "$repo"

    step "protect v*: only me create" \
      protect_v_tags_only_me_create "$repo" "$user_id"

    step "protect v*: immutable" \
      protect_v_tags_immutable "$repo"
  else
    skip "private vulnerability reporting" "public repositories only"
    skip "secret scanning + push protection" "not available on the current plan"
    skip "repository rulesets" "not available on the current plan"
  fi
done <<<"$repos"

if [[ "$failed" == "true" ]]; then
  exit 1
fi
