#!/usr/bin/env bash
# Article-level CTR by page_location (Mlytics 或 Readmo).
# Usage: ga4-article-ctr.sh <date_from> <date_to> <publish_date_from> [publish_date_to] [property_id] [source]
#   source: mlytics (default) | readmo

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required}"
DATE_TO="${2:?date_to required}"
PUBLISH_DATE_FROM="${3:?publish_date_from required}"
PUBLISH_DATE_TO="${4:-}"
PROPERTY_ID="${5:-}"
SOURCE_ARG="${6:-mlytics}"

BODY=$(jq -n \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --arg pdf "$PUBLISH_DATE_FROM" --arg pdt "$PUBLISH_DATE_TO" \
  --arg pid "$PROPERTY_ID" --arg src "$SOURCE_ARG" \
  '{date_from:$df, date_to:$dt, property_id:$pid, source:$src, publish_date_from:$pdf, publish_date_to:$pdt}')

api_curl POST /api/skill/ga4/article-ctr "$BODY"
