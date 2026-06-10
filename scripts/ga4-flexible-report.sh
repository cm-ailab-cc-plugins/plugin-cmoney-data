#!/usr/bin/env bash
# Run a GA4 flexible report — arbitrary dimensions + metrics + dimension_filter.
# Usage:
#   ga4-flexible-report.sh <date_from> <date_to> <event_names_csv> <dimensions_csv> \
#     [metrics_csv] [property_id] [dimension_filter_json] [order_by] [limit]
# Examples:
#   ga4-flexible-report.sh 2026-04-20 2026-04-27 readmo_questions_clicked customEvent:articleId
#   # top-5 頁面（server-side 排序+截斷，問「前 N 名」一定帶 order_by+limit）:
#   ga4-flexible-report.sh 2026-06-02 2026-06-08 page_view pageLocation eventCount 471029047 null eventCount 5
#   ga4-flexible-report.sh 2026-04-20 2026-04-27 readmo_questions_clicked date,customEvent:articleId eventCount 258250306 \
#     '{"customEvent:promptVariant":["開關廣告_A"],"customEvent:related_questions_ad_visible":["true"]}'
# Notes:
#   - dimensions / metrics 用 CSV，custom event 維度寫成 customEvent:<param_name>
#   - dimension_filter_json: 例 '{"customEvent:promptVariant":["A"]}'，預設 null
#   - order_by: 排序欄位（metric 或 dimension 名），預設降冪；limit: 最多回幾列（0=全量）
#     top-N 問題務必帶這兩個 — 全量高基數查詢可達數十萬列/數十秒，top-N 只要數秒
#   - 含中文時建議改寫到檔案再用 curl --data-binary @file，避免 shell 把 UTF-8 弄壞

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
EVENT_NAMES_CSV="${3:?event_names comma-separated required}"
DIMENSIONS_CSV="${4:?dimensions comma-separated required (e.g. customEvent:articleId)}"
METRICS_CSV="${5:-eventCount}"
PROPERTY_ID="${6:-}"
DIMENSION_FILTER="${7:-null}"
ORDER_BY="${8:-}"
LIMIT="${9:-0}"

EVENT_NAMES_JSON=$(echo "$EVENT_NAMES_CSV" | jq -R 'split(",")')
DIMENSIONS_JSON=$(echo "$DIMENSIONS_CSV" | jq -R 'split(",")')
METRICS_JSON=$(echo "$METRICS_CSV" | jq -R 'split(",")')

BODY=$(jq -n \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --argjson en "$EVENT_NAMES_JSON" \
  --argjson dims "$DIMENSIONS_JSON" \
  --argjson mets "$METRICS_JSON" \
  --arg pid "$PROPERTY_ID" \
  --argjson dfilter "$DIMENSION_FILTER" \
  --arg ob "$ORDER_BY" \
  --argjson lim "$LIMIT" \
  '{date_from:$df, date_to:$dt, event_names:$en, dimensions:$dims, metrics:$mets, property_id:$pid, dimension_filter:$dfilter}
    + (if $ob != "" then {order_by:$ob} else {} end)
    + (if $lim > 0 then {limit:$lim} else {} end)')

api_curl POST /api/skill/ga4/flexible-report "$BODY"
