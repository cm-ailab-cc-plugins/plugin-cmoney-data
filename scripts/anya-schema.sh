#!/usr/bin/env bash
# Fetch dataset + app_id schema from Anya backend.
# Usage: anya-schema.sh [full]
#   default — compact routing index (~24KB): id/app_id/display_name/type per
#             dataset; fetch one dataset's full schema via anya-dataset.sh
#   full    — legacy full registry (~360KB, overflows AI tool-output limits;
#             only use when you really need every schema_text at once)
# Output: JSON { datasets: [...], app_ids: [...] }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

MODE="${1:-compact}"
if [[ "$MODE" == "full" ]]; then
  api_curl GET /api/skill/schema
else
  api_curl GET "/api/skill/schema?compact=true"
fi
