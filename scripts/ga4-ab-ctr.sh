#!/usr/bin/env bash
# AB testing CTR (group-level views/clicks/CTR comparison).
# Usage: ga4-ab-ctr.sh <date_from> <date_to> <groups_json> [property_id] [daily_breakdown:true|false] [metric_type:eventCount|totalUsers] [publish_date_from] [publish_date_to]
# groups_json 範例:
#   '[{"name":"Mlytics_C","view_event":"readmo_questions_viewed","view_params":[],"click_event":"readmo_questions_clicked","click_params":[]}]'

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATE_FROM="${1:?date_from required}"
DATE_TO="${2:?date_to required}"
GROUPS_JSON="${3:?groups JSON required}"
PROPERTY_ID="${4:-}"
DAILY="${5:-false}"
METRIC_TYPE="${6:-eventCount}"
PUBLISH_FROM="${7:-}"
PUBLISH_TO="${8:-}"

BODY=$(jq -n \
  --arg df "$DATE_FROM" --arg dt "$DATE_TO" \
  --arg pid "$PROPERTY_ID" \
  --argjson grps "$GROUPS_JSON" \
  --argjson daily "$DAILY" \
  --arg mt "$METRIC_TYPE" \
  --arg pf "$PUBLISH_FROM" --arg pt "$PUBLISH_TO" \
  '{date_from:$df, date_to:$dt, property_id:$pid, groups:$grps, daily_breakdown:$daily, metric_type:$mt, publish_date_from:$pf, publish_date_to:$pt}')

api_curl POST /api/skill/ga4/ab-ctr "$BODY"
