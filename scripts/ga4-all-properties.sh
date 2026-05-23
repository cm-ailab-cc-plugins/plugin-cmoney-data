#!/usr/bin/env bash
# List ALL visible GA4 properties the service account can access (Admin API +
# registry merge). Use this instead of ga4-properties.sh when the question spans
# 「全部 CMoney 網站」 — ga4-properties.sh only returns the curated Blog/Forum/Readmo
# subset, this returns every accessible property (≈58).
# Usage: ga4-all-properties.sh
# Output: JSON { total, note, properties:[{id, display_name, account, hidden, order}] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

api_curl GET /api/skill/ga4/all-properties
