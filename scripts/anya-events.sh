#!/usr/bin/env bash
# Fetch event names for a given dataset + app_id.
# Usage: anya-events.sh <dataset_id> <app_id>
# Output: JSON { events: [...] }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATASET_ID="${1:?Usage: anya-events.sh <dataset_id> <app_id>}"
APP_ID="${2:?Usage: anya-events.sh <dataset_id> <app_id>}"

api_curl GET "/api/skill/events?dataset_id=${DATASET_ID}&app_id=${APP_ID}"