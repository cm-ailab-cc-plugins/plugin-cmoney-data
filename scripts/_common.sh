#!/usr/bin/env bash
# Common helpers for cmoney-data plugin scripts.
# sourced by login.sh / anya-*.sh / ga4-*.sh

set -euo pipefail

ANYA_SKILL_BASE_URL="${ANYA_SKILL_BASE_URL:-https://franky.ailabdev.cc}"
TOKEN_FILE="${HOME}/.anya-skill/token.json"

_need() {
  command -v "$1" > /dev/null 2>&1 || {
    echo "[cmoney-data] 找不到必要工具: $1。請先安裝 ($1)" >&2
    exit 1
  }
}

_need curl
_need jq

load_token() {
  if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "[cmoney-data] 尚未登入。請先執行:" >&2
    echo "  bash \"\$CLAUDE_PLUGIN_ROOT/scripts/login.sh\"" >&2
    exit 1
  fi
  local token
  token=$(jq -r '.access_token // empty' "$TOKEN_FILE")
  if [[ -z "$token" ]]; then
    echo "[cmoney-data] token 檔案內容異常 ($TOKEN_FILE)，請重新登入" >&2
    exit 1
  fi
  printf '%s' "$token"
}

# Usage: api_curl <method> <path> [body_json]
# Writes response body to stdout. Exits non-zero on HTTP >= 400.
# Auto-retries ONCE on 502/503/504 or curl transport failure (2s backoff):
# Anya/tunnel are transiently flaky, and a script-level retry costs 2s while
# bubbling the error up to the AI costs a whole model round-trip (10-20s).
# All skill calls are read-only queries, so retrying is safe.
api_curl() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local token
  token=$(load_token)
  local tmp
  tmp=$(mktemp)
  local http_code
  local attempt

  for attempt in 1 2; do
    if [[ -n "$body" ]]; then
      http_code=$(curl -sS -w "%{http_code}" -o "$tmp" -X "$method" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        --data-raw "$body" \
        "${ANYA_SKILL_BASE_URL}${path}") || http_code="000"
    else
      http_code=$(curl -sS -w "%{http_code}" -o "$tmp" -X "$method" \
        -H "Authorization: Bearer $token" \
        "${ANYA_SKILL_BASE_URL}${path}") || http_code="000"
    fi
    case "$http_code" in
      502|503|504|000)
        if [[ "$attempt" == "1" ]]; then
          echo "[cmoney-data] HTTP $http_code on $method $path — 2 秒後自動重試一次..." >&2
          sleep 2
          continue
        fi
        ;;
    esac
    break
  done

  if [[ "$http_code" == "401" ]]; then
    echo "[cmoney-data] Token 已失效或被撤銷 (HTTP 401)" >&2
    echo "  請重新執行: bash \"\$CLAUDE_PLUGIN_ROOT/scripts/login.sh\"" >&2
    cat "$tmp" >&2
    echo "" >&2
    rm -f "$tmp"
    exit 1
  fi

  if [[ "${http_code:-0}" -ge 400 ]]; then
    echo "[cmoney-data] HTTP $http_code on $method $path" >&2
    cat "$tmp" >&2
    echo "" >&2
    rm -f "$tmp"
    exit 1
  fi

  cat "$tmp"
  rm -f "$tmp"
}