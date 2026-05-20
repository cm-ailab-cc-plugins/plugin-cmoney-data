#!/usr/bin/env bash
# Daily trend of one metric for a single Threads account.
# Usage: threads-account-trend.sh <username> <date_from> <date_to> [metric]
#   metric: views(預設) | likes | replies | reposts | quotes
# Output: JSON { points: [ {username, date, value} ], cached_at, cache_ttl_seconds }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

USERNAME="${1:?username required}"
DATE_FROM="${2:?date_from required (YYYY-MM-DD)}"
DATE_TO="${3:?date_to required (YYYY-MM-DD)}"
METRIC="${4:-views}"

BODY=$(jq -n \
  --arg u "$USERNAME" \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --arg m "$METRIC" \
  '{username:$u, date_from:$df, date_to:$dt, metric:$m}')

api_curl POST /api/skill/threads/account-trend "$BODY"
