#!/usr/bin/env bash
# Fetch dataset + app_id schema from Anya backend.
# Usage: anya-schema.sh [full|refresh]
#   default — compact routing index (~24KB): id/app_id/display_name/type per
#             dataset; fetch one dataset's full schema via anya-dataset.sh.
#             Cached locally for 1h (~/.anya-skill/schema-cache.json) — the
#             registry rarely changes and this sits on every Anya query's hot
#             path. Pass "refresh" to bypass the local cache.
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
  exit 0
fi

CACHE_FILE="${HOME}/.anya-skill/schema-cache.json"
CACHE_TTL=3600

if [[ "$MODE" != "refresh" && -f "$CACHE_FILE" ]]; then
  now=$(date +%s)
  mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  if (( now - mtime < CACHE_TTL )) && jq -e '.datasets' "$CACHE_FILE" > /dev/null 2>&1; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

mkdir -p "$(dirname "$CACHE_FILE")"
TMP_OUT=$(mktemp)
api_curl GET "/api/skill/schema?compact=true" | tee "$TMP_OUT"
# Only persist a valid-looking payload so a failed/partial fetch never poisons
# the cache (api_curl exits non-zero on HTTP errors, killing us before here).
if jq -e '.datasets' "$TMP_OUT" > /dev/null 2>&1; then
  mv "$TMP_OUT" "$CACHE_FILE"
else
  rm -f "$TMP_OUT"
fi
