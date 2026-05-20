#!/usr/bin/env bash
# Aggregated Threads account metrics (views/likes/replies/reposts/quotes/followers/posts) over a date range.
# Usage: threads-account-metrics.sh <usernames_csv> <date_from> <date_to>
#   usernames_csv: 逗號分隔，例 "accountA,accountB"
# Output: JSON { accounts: [ {username, views, likes, ...} ], cached_at, cache_ttl_seconds }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

USERNAMES_CSV="${1:?usernames_csv required (comma-separated)}"
DATE_FROM="${2:?date_from required (YYYY-MM-DD)}"
DATE_TO="${3:?date_to required (YYYY-MM-DD)}"

USERNAMES_JSON=$(echo "$USERNAMES_CSV" | jq -R 'split(",") | map(select(length>0))')
BODY=$(jq -n \
  --argjson un "$USERNAMES_JSON" \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  '{usernames:$un, date_from:$df, date_to:$dt}')

api_curl POST /api/skill/threads/account-metrics "$BODY"
