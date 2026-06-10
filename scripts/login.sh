#!/usr/bin/env bash
# OAuth Device Flow login for cmoney-data plugin.
# Token 與 anya-query plugin 共用 (~/.anya-skill/token.json)，登過就不用再登。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_common.sh
source "${SCRIPT_DIR}/_common.sh"

# Short-circuit: 已登入「且 token 仍有效」才跳過。
# 過去只檢查檔案存在，token 過期時會誤判已登入、永遠不重新授權。
if [[ -f "$TOKEN_FILE" ]]; then
  existing_token=$(jq -r '.access_token // empty' "$TOKEN_FILE" 2>/dev/null || true)
  if [[ -n "$existing_token" ]]; then
    verify_code=$(curl -sS -m 10 -w "%{http_code}" -o /dev/null \
      -H "Authorization: Bearer $existing_token" \
      "${ANYA_SKILL_BASE_URL}/api/skill/schema" 2>/dev/null || echo "000")
    case "$verify_code" in
      200)
        echo "[cmoney-data login] 已登入且 token 有效（與 anya-query 共用: $TOKEN_FILE），跳過"
        exit 0
        ;;
      401|403)
        echo "[cmoney-data login] 既有 token 已失效 (HTTP $verify_code)，重新走授權流程..."
        ;;
      *)
        # 後端連不上（網路問題/維護）：重登也不會成功，保留現有 token 並提示
        echo "[cmoney-data login] 無法驗證 token（後端回 $verify_code），暫保留現有 token；若查詢失敗請稍後重跑本腳本"
        exit 0
        ;;
    esac
  fi
fi

echo "[cmoney-data login] 向後端請求 device code (${ANYA_SKILL_BASE_URL}) ..."

RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  --data-raw '{"client_name":"claude-code-cmoney-data"}' \
  "${ANYA_SKILL_BASE_URL}/api/auth/device/code")

DEVICE_CODE=$(echo "$RESP" | jq -r '.device_code // empty')
USER_CODE=$(echo "$RESP" | jq -r '.user_code // empty')
VERIFY_URL=$(echo "$RESP" | jq -r '.verification_uri_complete // .verification_uri // empty')
INTERVAL=$(echo "$RESP" | jq -r '.interval // 5')
EXPIRES_IN=$(echo "$RESP" | jq -r '.expires_in // 600')

if [[ -z "$DEVICE_CODE" || -z "$USER_CODE" || -z "$VERIFY_URL" ]]; then
  echo "[cmoney-data login] 後端回應異常:" >&2
  echo "$RESP" >&2
  exit 1
fi

cat <<EOF

================================
  cmoney-data 授權
================================

  user_code:  $USER_CODE

  授權網址:
    $VERIFY_URL

  請在 ${EXPIRES_IN} 秒內用 @cmoney.com.tw Google 帳號完成授權

================================

EOF

# 嘗試自動開啟瀏覽器（best-effort，失敗不影響流程）
if command -v start > /dev/null 2>&1; then
  # Windows / Git Bash
  start "" "$VERIFY_URL" > /dev/null 2>&1 || true
elif command -v cmd.exe > /dev/null 2>&1; then
  cmd.exe /c start "" "$VERIFY_URL" > /dev/null 2>&1 || true
elif command -v open > /dev/null 2>&1; then
  open "$VERIFY_URL" > /dev/null 2>&1 || true
elif command -v xdg-open > /dev/null 2>&1; then
  xdg-open "$VERIFY_URL" > /dev/null 2>&1 || true
fi

printf "[cmoney-data login] 等待授權"

ELAPSED=0
while [[ $ELAPSED -lt $EXPIRES_IN ]]; do
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))

  TMP=$(mktemp)
  HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -X POST \
    -H "Content-Type: application/json" \
    --data-raw "{\"device_code\":\"$DEVICE_CODE\"}" \
    "${ANYA_SKILL_BASE_URL}/api/auth/device/token")

  BODY=$(cat "$TMP")
  rm -f "$TMP"

  if [[ "$HTTP_CODE" == "200" ]]; then
    mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$BODY" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
    printf "\n"
    echo "[cmoney-data login] ✓ 授權成功，token 存於 $TOKEN_FILE"
    exit 0
  fi

  ERROR=$(echo "$BODY" | jq -r '.error // empty')
  case "$ERROR" in
    authorization_pending)
      printf "."
      ;;
    slow_down)
      INTERVAL=$((INTERVAL + 2))
      printf "s"
      ;;
    expired_token)
      printf "\n"
      echo "[cmoney-data login] ✗ device_code 已過期，請重新執行本腳本" >&2
      exit 1
      ;;
    access_denied)
      printf "\n"
      echo "[cmoney-data login] ✗ 使用者拒絕授權" >&2
      exit 1
      ;;
    *)
      printf "\n"
      echo "[cmoney-data login] ✗ 非預期回應 (HTTP $HTTP_CODE):" >&2
      echo "$BODY" >&2
      exit 1
      ;;
  esac
done

printf "\n"
echo "[cmoney-data login] ✗ 逾時，使用者未在 ${EXPIRES_IN} 秒內完成授權" >&2
exit 1