#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="hu553in"
REPO_LIMIT="200"

repos=(
  # "owner/repo"
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

edit_repo() {
  local repo="$1"

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
}

ruleset_id() {
  local repo="$1"
  local name="$2"
  local target="$3"

  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/rulesets?targets=$target" \
    --jq ".[] | select(.name == \"$name\") | .id" | head -n 1
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
    printf '%s' "$body" | gh api \
      -X PUT \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "repos/$repo/rulesets/$id" \
      --input -
  else
    printf '%s' "$body" | gh api \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "repos/$repo/rulesets" \
      --input -
  fi
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

user_id="$(gh api user --jq .id)"

if [ "${#repos[@]}" -gt 0 ]; then
  printf '%s\n' "${repos[@]}"
else
  for owner in "$USER_OWNER" $(gh org list); do
    gh repo list "$owner" --limit "$REPO_LIMIT" --source | awk '{print $1}'
  done
fi | while read -r repo; do
  echo
  echo "==> $repo"

  step "repo settings" \
    edit_repo "$repo"

  step "immutable releases" \
    gh api \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/immutable-releases"

  step "workflow permissions" \
    gh api \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/actions/permissions/workflow" \
    -F "default_workflow_permissions=write" \
    -F "can_approve_pull_request_reviews=false"

  step "private vulnerability reporting" \
    gh api \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/private-vulnerability-reporting"

  step "dependency graph + alerts" \
    gh api \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/vulnerability-alerts"

  step "dependabot security updates" \
    gh api \
    -X PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo/automated-security-fixes"

  step "secret scanning extras" \
    gh api \
    -X PATCH \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$repo" \
    -F "security_and_analysis[secret_scanning][status]=enabled" \
    -F "security_and_analysis[secret_scanning_push_protection][status]=enabled" \
    -F "security_and_analysis[secret_scanning_non_provider_patterns][status]=enabled" \
    -F "security_and_analysis[secret_scanning_validity_checks][status]=enabled"

  step "protect main: only me" \
    protect_main_only_me "$repo" "$user_id"

  step "protect main: no force push" \
    protect_main_no_force_push "$repo"

  step "protect v*: only me create" \
    protect_v_tags_only_me_create "$repo" "$user_id"

  step "protect v*: immutable" \
    protect_v_tags_immutable "$repo"
done
