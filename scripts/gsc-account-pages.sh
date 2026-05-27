#!/usr/bin/env bash
# Google Search Console per-article (per-URL) breakdown for one or more authors,
# split by surface (web/discover/...). 用來算「有曝光文章數」「曝光率」、看哪幾篇帶搜尋流量。
# Usage: gsc-account-pages.sh <date_from> <date_to> <user_ids_csv> [surfaces_csv] [site_url] [min_impressions] [top_n_per_account]
#   surfaces_csv 預設 web,discover（子集 of web/discover/googleNews/news）
#   min_impressions 過濾雜訊；top_n_per_account 限每作者篇數（0=不限）
# Output JSON: { date_from, date_to, site_url, surfaces,
#   by_account:[{ user_id, page_count, pages:[{ url, surfaces:{<s>:{clicks,impressions,ctr,position}}, all:{...} }] }] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
USER_IDS="${3:?user_ids_csv required}"
SURFACES="${4:-}"
SITE_URL="${5:-}"
MIN_IMPR="${6:-}"
TOP_N="${7:-}"

USER_IDS_JSON=$(echo "$USER_IDS" | jq -R 'split(",")')
JQ_ARGS=(--arg df "$DATE_FROM" --arg dt "$DATE_TO" --argjson uids "$USER_IDS_JSON")
FILTER='{date_from:$df, date_to:$dt, user_ids:$uids}'
if [ -n "$SURFACES" ]; then
  SURFACES_JSON=$(echo "$SURFACES" | jq -R 'split(",")')
  JQ_ARGS+=(--argjson surf "$SURFACES_JSON")
  FILTER="$FILTER + {surfaces:\$surf}"
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
  FILTER="$FILTER + {top_n_per_account:\$tn}"
fi
BODY=$(jq -n "${JQ_ARGS[@]}" "$FILTER")

api_curl POST /api/skill/gsc/account-pages "$BODY"
