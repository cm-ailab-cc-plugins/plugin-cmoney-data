#!/usr/bin/env bash
# Fetch dataset + app_id schema from Anya backend.
# Usage: anya-schema.sh
# Output: JSON { datasets: [...], app_ids: [...] }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

api_curl GET /api/skill/schema