#!/usr/bin/env bash
# List all available GA4 properties.
# Usage: ga4-properties.sh
# Output: JSON [{ id, name }, ...]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

api_curl GET /api/skill/ga4/properties