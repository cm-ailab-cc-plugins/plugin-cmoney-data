#!/usr/bin/env bash
# List custom param names available for a given GA4 event.
# Usage: ga4-event-params.sh <event_name> [property_id]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

EVENT_NAME="${1:?event_name required}"
PROPERTY_ID="${2:-}"

# URL-encode via jq (basic — assumes simple event names)
QS="event_name=$(printf %s "$EVENT_NAME" | jq -sRr @uri)"
[[ -n "$PROPERTY_ID" ]] && QS="$QS&property_id=$(printf %s "$PROPERTY_ID" | jq -sRr @uri)"

api_curl GET "/api/skill/ga4/event-params?${QS}"
