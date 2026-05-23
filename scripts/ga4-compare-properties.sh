#!/usr/bin/env bash
# Compare a single GA4 metric across ALL visible properties (or a given subset)
# over a date range, optionally vs a baseline period. Backend fans out in parallel
# and returns rows ranked by growth_pct desc. Core of the「哪個站成長最多」use case.
# Usage: ga4-compare-properties.sh <metric> <date_from> <date_to> [compare_from] [compare_to] [property_ids_csv]
#   metric: e.g. sessions / activeUsers / screenPageViews / eventCount
#   compare_from/compare_to: baseline period for growth_pct (omit = no growth calc)
#   property_ids_csv: omit = all visible properties
# Output: JSON { metric, total, properties:[{id, display_name, value, compare_value, growth_pct}] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

METRIC="${1:?metric required (e.g. sessions)}"
DATE_FROM="${2:?date_from required (YYYY-MM-DD)}"
DATE_TO="${3:?date_to required (YYYY-MM-DD)}"
COMPARE_FROM="${4:-}"
COMPARE_TO="${5:-}"
PROPERTY_IDS="${6:-}"

enc() { printf '%s' "$1" | jq -sRr @uri; }

QS="metric=$(enc "$METRIC")&date_from=$(enc "$DATE_FROM")&date_to=$(enc "$DATE_TO")"
[ -n "$COMPARE_FROM" ] && QS="$QS&compare_from=$(enc "$COMPARE_FROM")"
[ -n "$COMPARE_TO" ] && QS="$QS&compare_to=$(enc "$COMPARE_TO")"
[ -n "$PROPERTY_IDS" ] && QS="$QS&property_ids=$(enc "$PROPERTY_IDS")"

api_curl GET "/api/skill/ga4/compare-properties?${QS}"
