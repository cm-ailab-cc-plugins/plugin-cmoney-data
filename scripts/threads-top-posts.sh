#!/usr/bin/env bash
# Top Threads posts by views over a date range (per-post views/likes/replies/reposts/quotes/shares).
# Usage: threads-top-posts.sh <usernames_csv> <date_from> <date_to> [limit]
#   limit 預設 10、硬上限 50
# Output: JSON { posts: [ {username, post_id, text, permalink, timestamp, views, ...} ], cached_at, cache_ttl_seconds }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

USERNAMES_CSV="${1:?usernames_csv required (comma-separated)}"
DATE_FROM="${2:?date_from required (YYYY-MM-DD)}"
DATE_TO="${3:?date_to required (YYYY-MM-DD)}"
LIMIT="${4:-10}"

USERNAMES_JSON=$(echo "$USERNAMES_CSV" | jq -R 'split(",") | map(select(length>0))')
BODY=$(jq -n \
  --argjson un "$USERNAMES_JSON" \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --argjson limit "$LIMIT" \
  '{usernames:$un, date_from:$df, date_to:$dt, limit:$limit}')

api_curl POST /api/skill/threads/top-posts "$BODY"
