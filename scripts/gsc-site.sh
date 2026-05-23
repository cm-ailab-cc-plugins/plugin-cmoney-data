#!/usr/bin/env bash
# Google Search Console site-level totals over a date range, split by surface
# (web / discover / googleNews / news / all). Each block has clicks, impressions,
# ctr, position.
# Usage: gsc-site.sh <date_from> <date_to> [site_url]
#   site_url omitted = backend default (sc-domain:cmnews.com.tw). Run gsc-sites.sh to list options.
# Output: JSON { date_from, date_to, site_url, totals:{web,discover,googleNews,news,all} }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required (YYYY-MM-DD)}"
DATE_TO="${2:?date_to required (YYYY-MM-DD)}"
SITE_URL="${3:-}"

if [ -n "$SITE_URL" ]; then
  BODY=$(jq -n --arg df "$DATE_FROM" --arg dt "$DATE_TO" --arg su "$SITE_URL" \
    '{date_from:$df, date_to:$dt, site_url:$su}')
else
  BODY=$(jq -n --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
    '{date_from:$df, date_to:$dt}')
fi

api_curl POST /api/skill/gsc/site "$BODY"
