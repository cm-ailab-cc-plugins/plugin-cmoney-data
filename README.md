# cmoney-data

Claude Code plugin — 整合 Anya 使用者行為資料 + Readmo GA4 + Threads 帳號成效查詢。

OAuth 授權後讓 Claude Code 直接：
- 生 Spark SQL 查 Anya（SDK 埋點事件，例如 launch/click）
- 打 Readmo GA4 report API（page_view、CTR、AB 測試比較）
- 查公司經營的 Threads 帳號發文成效（views/likes/followers、Top 貼文、逐日趨勢）

每次查詢都寫 audit log，Anya / GA4 / Threads 共用 60 req/min rate limit。

## 安裝

```
/plugin marketplace add kevinchang-art/my-claude-plugins
/plugin install cmoney-data
```

## 需求

- `bash`（Windows 請用 Git Bash）
- `jq`
- `curl`

## Token 共用

與 [plugin-anya-query](https://github.com/kevinchang-art/plugin-anya-query) 共用 `~/.anya-skill/token.json`。已登過就不用再登；未登時跑：

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/login.sh"
```

## 包含腳本

### Auth & 共用
- `login.sh` — OAuth Device Flow 授權（已登過會 short-circuit）
- `_common.sh` — token 載入 + `api_curl` HTTP wrapper（401/4xx/5xx 處理）

### Anya
- `anya-schema.sh` — 列 datasets + app_ids
- `anya-events.sh <dataset_id> <app_id>` — 列指定 dataset/app 的 event 名稱
- `anya-query.sh '<SQL>' [row_limit] [dataset_id] [app_id]` — 執行 Spark SQL

### GA4
- `ga4-properties.sh` — 列可用 GA4 property
- `ga4-report.sh <date_from> <date_to> <event_names_csv> [property_id] [dimension_filter_json]` — 日報表
- `ga4-article-ctr.sh <date_from> <date_to> <publish_date_from> [publish_date_to] [property_id] [source]` — 文章 CTR (mlytics/readmo)
- `ga4-ab-ctr.sh <date_from> <date_to> <groups_json> [property_id] [daily] [metric_type] [publish_from] [publish_to]` — AB 測試 CTR
- `ga4-event-params.sh <event_name> [property_id]` — 列某 event 的 custom param 名稱
- `ga4-param-values.sh <event_name> <param_name> [property_id]` — 列某 param 的值清單

### Threads
- `threads-accounts.sh` — 列已設定的 Threads 帳號
- `threads-account-metrics.sh <usernames_csv> <date_from> <date_to>` — 帳號彙總成效（views/likes/followers/posts）
- `threads-top-posts.sh <usernames_csv> <date_from> <date_to> [limit]` — Top 貼文（依 views，預設 10）
- `threads-account-trend.sh <username> <date_from> <date_to> [metric]` — 單帳號逐日趨勢（views/likes/replies/reposts/quotes）

## 使用方式

安裝完直接用中文問 Claude Code，例：
- 「昨天 readmo app launch 幾次？」（Anya）
- 「上週 Readmo Blog page_view 趨勢？」（GA4）
- 「過去 7 天 Mlytics_C vs Control CTR 比較」（GA4 AB）
- 「我們的 Threads 帳號上週成效？」（Threads）
- 「accountA 上週哪幾篇最紅 + views 趨勢」（Threads）

skill (`skills/cmoney-data/SKILL.md`) 會引導 Claude Code 自動判斷該走 Anya / GA4 / Threads 路徑。
