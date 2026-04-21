#!/usr/bin/env bash

set -euo pipefail

SECRET_NAME="GHCR_PAT"
SECRET_VALUE=""

REPOS=(
  hu553in/spa-crawler
  hu553in/gdrive-assistant-bot
  hu553in/keenetic-vpn-switcher
  hu553in/grooming-studio-chat-helper
  hu553in/yandex-alice-openai
  hu553in/grooming-studio-api
  hu553in/dockguard
  hu553in/telekilogram
  hu553in/swaggerhub-latest-proxy
  hu553in/tempstream
  hu553in/invites-keycloak
  hu553in/grooming-studio
  hu553in/wotd-bot
  hu553in/cash-bot
  hu553in/tizen-tool
  hu553in/single-deployment
)

for repo in "${REPOS[@]}"; do
  gh secret set "$SECRET_NAME" \
    --app dependabot \
    --repo "$repo" \
    --body "$SECRET_VALUE"
done
