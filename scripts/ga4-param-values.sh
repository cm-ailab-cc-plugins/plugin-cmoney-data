#!/usr/bin/env bash
# List distinct values for a given (event_name, param_name).
# Usage: ga4-param-values.sh <event_name> <param_name> [property_id]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

EVENT_NAME="${1:?event_name required}"
PARAM_NAME="${2:?param_name required}"
PROPERTY_ID="${3:-}"

QS="event_name=$(printf %s "$EVENT_NAME" | jq -sRr @uri)"
QS="$QS&param_name=$(printf %s "$PARAM_NAME" | jq -sRr @uri)"
[[ -n "$PROPERTY_ID" ]] && QS="$QS&property_id=$(printf %s "$PROPERTY_ID" | jq -sRr @uri)"

api_curl GET "/api/skill/ga4/param-values?${QS}"
