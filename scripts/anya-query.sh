#!/usr/bin/env bash
# Execute a Spark SQL against Anya via backend.
# Usage: anya-query.sh '<SQL>' [row_limit] [dataset_id] [app_id]
# Output: JSON { columns, rows, row_count, truncated, elapsed_ms }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

SQL="${1:?Usage: anya-query.sh '<SQL>' [row_limit] [dataset_id] [app_id]}"
ROW_LIMIT="${2:-1000}"
DATASET_ID="${3:-}"
APP_ID="${4:-}"

BODY=$(jq -n \
  --arg sql "$SQL" \
  --argjson row_limit "$ROW_LIMIT" \
  --arg dataset_id "$DATASET_ID" \
  --arg app_id "$APP_ID" \
  '{sql: $sql, row_limit: $row_limit}
    + (if $dataset_id != "" then {dataset_id: $dataset_id} else {} end)
    + (if $app_id != "" then {app_id: $app_id} else {} end)')

api_curl POST /api/skill/execute "$BODY"