#!/usr/bin/env bash
# Flexible Google Search Console breakdown by arbitrary dimensions x surfaces.
#   per-query（哪些字帶量）/ per-country / per-device / 逐日（date）/ per-page。
# Usage: gsc-breakdown.sh <date_from> <date_to> <dimensions_csv> [surfaces_csv] [user_ids_csv] [site_url] [min_impressions] [top_n]
#   dimensions_csv: 子集 of date,query,page,country,device（query 只有 web surface）
#   surfaces_csv 預設 web ; user_ids_csv → 作者歸因，回傳改 nest by_account
# Output JSON: { date_from, date_to, site_url, dimensions, surfaces,
#   rows:[{ keys:{<dim>:value}, surfaces:{<s>:{clicks,impressions,ctr,position}}, all:{...} }] }
#   或給 user_ids 時: { ..., by_account:[{ user_id, row_count, rows:[...] }] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
DIMENSIONS="${3:?dimensions_csv required (subset of date,query,page,country,device)}"
SURFACES="${4:-}"
USER_IDS="${5:-}"
SITE_URL="${6:-}"
MIN_IMPR="${7:-}"
TOP_N="${8:-}"

DIMS_JSON=$(echo "$DIMENSIONS" | jq -R 'split(",")')
JQ_ARGS=(--arg df "$DATE_FROM" --arg dt "$DATE_TO" --argjson dims "$DIMS_JSON")
FILTER='{date_from:$df, date_to:$dt, dimensions:$dims}'
if [ -n "$SURFACES" ]; then
  SURFACES_JSON=$(echo "$SURFACES" | jq -R 'split(",")')
  JQ_ARGS+=(--argjson surf "$SURFACES_JSON")
  FILTER="$FILTER + {surfaces:\$surf}"
fi
if [ -n "$USER_IDS" ]; then
  USER_IDS_JSON=$(echo "$USER_IDS" | jq -R 'split(",")')
  JQ_ARGS+=(--argjson uids "$USER_IDS_JSON")
  FILTER="$FILTER + {user_ids:\$uids}"
fi
if [ -n "$SITE_URL" ]; then
  JQ_ARGS+=(--arg site "$SITE_URL")
  FILTER="$FILTER + {site_url:\$site}"
fi
if [ -n "$MIN_IMPR" ]; then
  JQ_ARGS+=(--argjson mi "$MIN_IMPR")
  FILTER="$FILTER + {min_impressions:\$mi}"
fi
if [ -n "$TOP_N" ]; then
  JQ_ARGS+=(--argjson tn "$TOP_N")
  FILTER="$FILTER + {top_n:\$tn}"
fi
BODY=$(jq -n "${JQ_ARGS[@]}" "$FILTER")

api_curl POST /api/skill/gsc/breakdown "$BODY"
