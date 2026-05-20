#!/usr/bin/env bash
# List configured Threads accounts (usernames only, no tokens).
# Usage: threads-accounts.sh
# Output: JSON { accounts: [ { username } ] }

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

api_curl GET /api/skill/threads/accounts
