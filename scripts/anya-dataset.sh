#!/usr/bin/env bash
# Fetch ONE dataset's full registry entry (schema_text, extra_tables, column
# config). Pair with the compact index from anya-schema.sh: route the question
# with the index, then pull detail only for the dataset you actually query.
# Usage: anya-dataset.sh <dataset_id>
# Output: JSON {id, app_id, display_name, anya_table, event_name_col, schema_text, extra_tables, ...}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

DATASET_ID="${1:?Usage: anya-dataset.sh <dataset_id>}"

api_curl GET "/api/skill/schema/dataset/${DATASET_ID}"
