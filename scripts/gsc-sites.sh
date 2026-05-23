#!/usr/bin/env bash
# List the Google Search Console sites the service account can access.
# Usage: gsc-sites.sh
# Output: JSON { sites:[{site_url, permission_level}] }
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

api_curl GET /api/skill/gsc/sites
