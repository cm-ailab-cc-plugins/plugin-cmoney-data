#!/usr/bin/env bash
# Run a GA4 daily report (date x event x device).
# Usage: ga4-report.sh <date_from> <date_to> <event_names_csv> [property_id] [dimension_filter_json]
#   dimension_filter_json: 例 '{"page_location":["https://blog.cmoney.tw/article/123"]}'，預設 null

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
EVENT_NAMES_CSV="${3:?event_names comma-separated required}"
PROPERTY_ID="${4:-}"
DIMENSION_FILTER="${5:-null}"

EVENT_NAMES_JSON=$(echo "$EVENT_NAMES_CSV" | jq -R 'split(",")')
BODY=$(jq -n \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --argjson en "$EVENT_NAMES_JSON" \
  --arg pid "$PROPERTY_ID" \
  --argjson dfilter "$DIMENSION_FILTER" \
  '{date_from:$df, date_to:$dt, event_names:$en, property_id:$pid, dimension_filter:$dfilter}')

api_curl POST /api/skill/ga4/report "$BODY"