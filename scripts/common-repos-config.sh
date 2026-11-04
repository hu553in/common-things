#!/usr/bin/env bash

set -euo pipefail

USER_OWNER="${USER_OWNER:-hu553in}"
REPO_LIMIT="${REPO_LIMIT:-200}"
REPOS="${REPOS:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESERVE_FILE="${RESERVE_FILE:-$SCRIPT_DIR/../reserve-repos.json}"
RENOVATE_APP_ID=2740
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

# GitHub rejects these writes on archived repositories, which are read-only.
writable_step() {
  if [[ "$archived" == "true" ]]; then
    skip "$1" "archived"
  else
    step "$@"
  fi
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

# Merge settings are left alone: reserve repositories have pull requests disabled.
edit_reserve_repo() {
  local repo="$1"

  gh repo edit "$repo" \
    --default-branch main \
    --enable-issues=false \
    --enable-projects=false \
    --enable-discussions=false \
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

# Actions are only switched on when disabled, so the allowed-actions policy is left as it is.
enable_actions() {
  local repo="$1"
  local enabled

  enabled="$(github_api "repos/$repo/actions/permissions" --jq .enabled)" || return 1
  if [[ "$enabled" != "true" ]]; then
    github_api -X PUT "repos/$repo/actions/permissions" -F enabled=true
  fi
}

is_reserve() {
  local repo="$1"

  [[ "${repo%%/*}" == "$USER_OWNER" ]] && grep -Fxq -- "${repo#*/}" <<<"$reserve_repos"
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

  if [[ -n "$id" ]]; then
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
  if [[ -n "$REPOS" ]]; then
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
  local renovate="$3"
  local renovate_bypass=""

  if [[ "$renovate" == "true" ]]; then
    renovate_bypass=",
    {
      \"actor_id\": $RENOVATE_APP_ID,
      \"actor_type\": \"Integration\",
      \"bypass_mode\": \"pull_request\"
    }"
  fi

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
    }$renovate_bypass
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
  local user_id="$2"

  put_ruleset "$repo" "main: no force pushes" "branch" "$(
    cat <<EOF
{
  "name": "main: no force pushes",
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
  local excludes="$3"

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
      "exclude": $excludes
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
  local excludes="$2"

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
      "exclude": $excludes
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

reserve_repos="$(jq -r '.[]' "$RESERVE_FILE")"
user_id="$(github_api user --jq .id)"

repos="$(repo_list)"

while read -r repo; do
  [[ -z "$repo" ]] && continue

  # GitHub resolves names case-insensitively; the canonical name is what the reserve list holds.
  repo_info="$(github_api "repos/$repo" --jq '"\(.full_name) \(.visibility) \(.archived)"')"
  read -r repo visibility archived <<<"$repo_info"
  floating_major_tags="[]"
  if [[ "$repo" == "$USER_OWNER/ascii-profile-card" ]]; then
    floating_major_tags='["refs/tags/v[0-9]", "refs/tags/v[0-9][0-9]", "refs/tags/v[0-9][0-9][0-9]"]'
  fi
  can_approve_pull_request_reviews=false
  if [[ "$repo" == "$USER_OWNER/homebrew-tap" ]]; then
    can_approve_pull_request_reviews=true
  fi
  reserve=false
  if is_reserve "$repo"; then
    reserve=true
  fi

  echo
  if [[ "$reserve" == "true" ]]; then
    echo "==> $repo (reserve)"
  else
    echo "==> $repo"
  fi

  step "immutable releases" \
    github_api \
    -X PUT \
    "repos/$repo/immutable-releases"

  if [[ "$reserve" == "true" ]]; then
    writable_step "repo settings" \
      edit_reserve_repo "$repo"

    writable_step "disable pull requests" \
      github_api \
      -X PATCH \
      "repos/$repo" \
      -F has_pull_requests=false

    # Dependabot security updates go off with the alerts, and GitHub rejects configuring them then.
    writable_step "disable dependency graph + alerts" \
      github_api \
      -X DELETE \
      "repos/$repo/vulnerability-alerts"

    step "disable actions" \
      github_api \
      -X PUT \
      "repos/$repo/actions/permissions" \
      -F enabled=false

    skip "workflow permissions" "actions disabled"
  else
    # Pull requests, Actions, and alerts are switched on before the steps that configure them.
    writable_step "enable pull requests" \
      github_api \
      -X PATCH \
      "repos/$repo" \
      -F has_pull_requests=true

    writable_step "repo settings" \
      edit_repo "$repo"

    step "enable actions" \
      enable_actions "$repo"

    step "workflow permissions" \
      github_api \
      -X PUT \
      "repos/$repo/actions/permissions/workflow" \
      -F "default_workflow_permissions=read" \
      -F "can_approve_pull_request_reviews=$can_approve_pull_request_reviews"

    writable_step "dependency graph + alerts" \
      github_api \
      -X PUT \
      "repos/$repo/vulnerability-alerts"

    # Renovate reads Dependabot alerts but owns the remediation pull requests.
    writable_step "disable dependabot security updates" \
      github_api \
      -X DELETE \
      "repos/$repo/automated-security-fixes"
  fi

  if [[ "$visibility" == "public" ]]; then
    if [[ "$reserve" == "true" ]]; then
      writable_step "disable private vulnerability reporting" \
        github_api \
        -X DELETE \
        "repos/$repo/private-vulnerability-reporting"
    else
      writable_step "private vulnerability reporting" \
        github_api \
        -X PUT \
        "repos/$repo/private-vulnerability-reporting"
    fi

    step "secret scanning + push protection" \
      enable_secret_scanning "$repo"

    if [[ "$reserve" == "true" ]]; then
      writable_step "protect main: only me" \
        protect_main_only_me "$repo" "$user_id" false
    else
      writable_step "protect main: only me and Renovate" \
        protect_main_only_me "$repo" "$user_id" true
    fi

    writable_step "protect main: no force push" \
      protect_main_no_force_push "$repo" "$user_id"

    writable_step "protect v*: only me create" \
      protect_v_tags_only_me_create "$repo" "$user_id" "$floating_major_tags"

    writable_step "protect v*: immutable" \
      protect_v_tags_immutable "$repo" "$floating_major_tags"
  else
    skip "private vulnerability reporting" "public repositories only"
    skip "secret scanning + push protection" "not available on the current plan"
    skip "repository rulesets" "not available on the current plan"
  fi
done <<<"$repos"

if [[ "$failed" == "true" ]]; then
  exit 1
fi
