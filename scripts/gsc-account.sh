#!/usr/bin/env bash
# Google Search Console per-account breakdown over a date range.
#   - no user_ids → whole-site aggregate (by_account empty)
#   - with user_ids → per-account split
# Usage: gsc-account.sh <date_from> <date_to> [user_ids_csv] [top_n]
# Output: JSON { date_from, date_to, site_url, aggregate:{...}, by_account:[{user_id, totals:{...}}] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
USER_IDS="${3:-}"
TOP_N="${4:-}"

JQ_ARGS=(--arg df "$DATE_FROM" --arg dt "$DATE_TO")
FILTER='{date_from:$df, date_to:$dt}'
if [ -n "$USER_IDS" ]; then
  USER_IDS_JSON=$(echo "$USER_IDS" | jq -R 'split(",")')
  JQ_ARGS+=(--argjson uids "$USER_IDS_JSON")
  FILTER="$FILTER + {user_ids:\$uids}"
fi
if [ -n "$TOP_N" ]; then
  JQ_ARGS+=(--argjson tn "$TOP_N")
  FILTER="$FILTER + {top_n:\$tn}"
fi
BODY=$(jq -n "${JQ_ARGS[@]}" "$FILTER")

api_curl POST /api/skill/gsc/account "$BODY"
