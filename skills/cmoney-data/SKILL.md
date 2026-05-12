---
name: cmoney-data
description: Anya + Readmo GA4 整合查詢工具 — 用中文問題查 CMoney 內部使用者行為（Anya / Spark SQL）與 Readmo Web 分析（GA4）。OAuth 授權後 Claude Code 直接生 SQL 或 GA4 report request 取資料，每次查詢都寫 audit log。適用於「昨天理財寶 launch 次數」「上週 Readmo Blog page_view」「Mlytics_C vs Control CTR 比較」「OneLink 點擊歸因」等問題。
---

# CMoney 資料查詢 Skill (Anya + Readmo GA4)

你（Claude Code）要幫使用者用中文問題查 CMoney 內部資料 — 涵蓋兩個來源：
- **Anya**：使用者行為事件（SDK 埋點，Spark SQL）
- **Readmo GA4**：Readmo Web property（投資網誌 / 討論區 / 文章子網域）pageview / CTR / AB 測試

流程：確認登入 → 路徑判斷 → 查對應子流程 → 呈現結果。

## 前置：檢查 token

執行任何查詢前確認 token：
```bash
test -f "$HOME/.anya-skill/token.json" || bash "${CLAUDE_PLUGIN_ROOT}/scripts/login.sh"
```

若 token 不存在，跑 login 腳本，它會：
1. 向後端要 device code
2. 列印 user_code + 瀏覽器 URL（並嘗試自動開啟）
3. Polling 後端直到使用者在瀏覽器按下授權
4. 存 access_token 到 `~/.anya-skill/token.json`

使用者看到 URL 後會用 Google 登入（限 @cmoney.com.tw）並按授權。token 與既有 anya-query plugin 共用同一檔案，登過就不用再登。

## 路徑判斷（先做這個）

| 線索 | 路徑 |
|---|---|
| 提到 app_id、SDK 事件、launch/click 等內部埋點 | Anya |
| 提到 ext_userbehavior_v2、trans_onelink_*、Spark SQL | Anya |
| 理財寶、CMoney app 行為資料 | Anya |
| OneLink 點擊歸因 | Anya |
| 同學會家族（股市爆料 18 / 新聞爆料 38 / 美股爆料 55 / 加密貨幣 128 / 追劇 136 / 海外 249）user-level 數據 | Anya（見 Cookbook） |
| Readmo Blog/Forum、page_view、page_location、文章 CTR | GA4 |
| AB 測試 CTR (group 比較) | GA4 |
| pageTitle / engagement / session metrics | GA4 |
| 不確定 | 先列 GA4 properties + Anya schema 兩邊都看 |

---

## Anya 子流程

### 1. 拉註冊 schema（每次 session 第一次 Anya 查詢時執行）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/anya-schema.sh"
```

回傳 JSON `{datasets: [...], app_ids: [...]}`。**註冊 dataset 是 hint，不是硬性限制 — 使用者也可以查任何其他 Anya 表，只是沒有預先整理好的 schema_text**。

每個 dataset 有：
- `id` — dataset 識別碼
- `name` — 顯示名稱
- `anya_table` — 實際要查的 Spark table（例如 `ext_userbehavior_v2`）
- `app_id` — 綁定的 app id
- `event_name_col` — 事件名稱欄位（例如 `object.eventName`）
- `schema_text` — 完整欄位說明
- `extra_tables` — 同 app 的附表

### 2. 判斷查哪張表

分三種情況處理：

#### A. 問題對應到註冊 dataset（最常見）

例如「理財寶 launch 次數」→ app_id=1 的事件表。
- 直接用 dataset 的 `anya_table` + `schema_text` 產生 SQL
- 跑 `anya-events.sh <dataset_id> <app_id>` 確認事件名稱存在

#### B. 問題對應 OneLink（已知不在註冊 dataset）

OneLink 點擊歸因走以下三張表：

| 表 | 欄位 |
|---|---|
| `trans_onelink_clickcounts` | `onelink`(string), `click_date`(date), `click_counts`(bigint) |
| `trans_onelink_activity_link` | `redirectlinkkey`, `appid`, `activityname`, `medium`, `category` |
| `trans_onelink_memberid` | `appid`, `click_date`, `info_redirect_key`, `memberid`, `platform`, `open_date`, `open_type` |

典型 JOIN：`trans_onelink_clickcounts.onelink = trans_onelink_activity_link.redirectlinkkey`

#### C. 其他 / 未知表

- 用 `SHOW TABLES` 列出所有可見 table
- 找出候選 table 後用 `DESCRIBE <table>` 看欄位
- 必要時 `SELECT * FROM <table> LIMIT 5` 實際看幾筆資料
- 後端允許 `SHOW` / `DESCRIBE` / `DESC` / `EXPLAIN` / `SELECT` / `WITH`（仍禁 INSERT/UPDATE/DELETE/DROP/CREATE/ALTER/TRUNCATE）

#### Anya table 命名慣例

- `ext_*` — 原始事件表（由 SDK / 埋點產出），通常有 `app_id` 欄位
- `trans_*` — transformation 表（ETL 計算結果），欄位依邏輯而定
- `dim_*` / `mart_*` — 維度 / 分析結果表（若有）

### 3. 生 Spark SQL — 守則

1. **多 app 事件表要加 app_id filter**：`ext_userbehavior_v2` 等共用表一定要 `WHERE app_id = <n>`。App 專屬表或 `trans_*` 表看欄位而定，不一定有 app_id
2. **日期用 DATE literal**：`txDate = DATE 'YYYY-MM-DD'` 或 `BETWEEN DATE '...' AND DATE '...'`
3. **事件名稱用 dataset 指定的欄位**：若 `event_name_col = "object.eventName"` → `object.eventName = 'launch'`
4. **時區**：使用者說「昨天」、「最近 7 天」時用當天日期換算。今天日期從 Claude Code 環境取得
5. **探索先 LIMIT 10**：沒看過的 table，先 `SELECT * FROM ... LIMIT 10` 確認欄位長相再寫聚合
6. **結果行數限制**：最外層結果 row 數盡量 < 1000（row_limit 預設 1000、硬上限 5000）。要更多就分批或改聚合
7. **允許的語句**：SELECT / WITH / SHOW / DESCRIBE / EXPLAIN
8. **禁止的語句**：INSERT / UPDATE / DELETE / DROP / CREATE / ALTER / TRUNCATE（後端會擋，請不要 workaround）

### 4. 執行 SQL

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/anya-query.sh" '<SQL>' [row_limit] [dataset_id] [app_id]
```

`row_limit` 預設 1000、硬上限 5000。`dataset_id` 與 `app_id` 供 audit 用，不影響查詢（查哪張表由 SQL 決定）；若查的不是註冊 dataset，可省略或傳空字串。

回傳：
```json
{
  "columns": ["col1", "col2"],
  "rows": [["v1", "v2"], ...],
  "row_count": 42,
  "truncated": false,
  "elapsed_ms": 1234
}
```

### 5. 呈現結果

- 用 markdown 表格呈現（columns → 表頭，rows → 表身）
- `row_count` < 10 全顯；多的話只顯示前 20 行 + 註明 "共 N 筆"
- 若 `truncated: true` → 明確告訴使用者「結果被截斷到 1000 筆，可能遺漏。建議改聚合 / 縮小時間範圍」
- 提供後續建議：要不要往下鑽（by app_version / by platform）、要不要改成趨勢圖、要不要對比其他時間段

---

## GA4 子流程

### 1. 列出可用 property

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-properties.sh"
```

預期 property（後端 env 設）：
- Blog 投資網誌（`BLOG_GA4_PROPERTY_ID`）
- Forum 討論區（`FORUM_GA4_PROPERTY_ID`）
- Readmo 文章子網域 = `505661605`（hardcode）

### 2. 探索 event 與 param（必要時）

如果不確定某 event 有哪些 custom param：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-event-params.sh" "<event_name>" "<property_id>"
```

如果想知道某 param 有哪些值：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-param-values.sh" "<event_name>" "<param_name>" "<property_id>"
```

### 3. 跑報表

**A. 一般日報表（date × event）**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-report.sh" "2026-04-20" "2026-04-26" "page_view,scroll" "<property_id>"
```
回每日 metrics（含 device_category 拆分）。

**B. 文章 CTR**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-article-ctr.sh" "<date_from>" "<date_to>" "<publish_date_from>" "<publish_date_to>" "<property_id>" "mlytics|readmo"
```
依 page_location 維度算每篇文章的 impressions / clicks / CTR。

**C. AB 測試 CTR**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-ab-ctr.sh" "<date_from>" "<date_to>" '<groups_json>' "<property_id>" [daily:true/false]
```
groups_json 範例：
```json
[{"name":"Mlytics_C","view_event":"readmo_questions_viewed","view_params":[],"click_event":"readmo_questions_clicked","click_params":[]}]
```

**D. 任意維度報表（flexible report）**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-flexible-report.sh" \
  "<date_from>" "<date_to>" "<event_names_csv>" "<dimensions_csv>" \
  [metrics_csv] [property_id] [dimension_filter_json]
```
- `dimensions_csv`：用 CSV，custom event 維度寫成 `customEvent:<param_name>`，內建維度直接寫名（如 `date`, `deviceCategory`）
- `metrics_csv`：預設 `eventCount`
- `dimension_filter_json`：filter key 也是 GA4 dim 名（custom 維度同樣加 `customEvent:` 前綴）

什麼時候用：要按 articleId / page_title / 任意 custom 維度做 group by，或要 filter 多個 custom param 後算總量。
含中文 filter 值時改用 curl + body 檔（範例見「範例 F」）。

### 4. 呈現

- markdown 表格
- 結果多就只顯示 top 20 + 註明總筆數
- 後續建議：要不要拆 device、看趨勢、加 publish date filter 等

---

## Cookbook：同學會 user-level 數據

「同學會」家族（股市爆料 18 / 新聞爆料 38 / 美股爆料 55 / 加密貨幣 128 / 追劇 136 / 海外 249）user-level 數據，以下表是 **2026-04 驗證過的新鮮來源**。直接套用，不必再 SHOW TABLES / DESCRIBE。下面 SQL 範例以股市爆料同學會（appid=18, dataset=e541e992）為例。

### 對應表（**fresh，可用**）

| 指標 | 表 | 關鍵欄位 | 過濾 |
|---|---|---|---|
| 追蹤者數 | `ext_forum_member_follow` | `FollowMemberId` (BIGINT)、`MemberId` | `WHERE FollowMemberId = <user>` → `COUNT(*)` |
| 貼文清單 | `trans_forum_articles` | `articleid`、`creatorid` (string)、`title`、`createtime` (timestamp ms 字串)、`deleted` (int)、`kafka_event_date` | `WHERE creatorid='<user>' AND deleted=0` |
| 瀏覽事件 | `trans_forum_article_reads` | `articleid`、`memberid` (reader)、`event_name`、`view_type`、`event_date` | `WHERE event_name='Article_read' AND event_date >= '<from>'` |
| 留言事件 | `trans_comment_record_all` | `articleid`、`memberid`、`action_type` (1=create, -1=delete)、`event_date` | `WHERE appid=<app> AND event_date >= '<from>'` |
| 按讚/反應事件 | `trans_reaction_record_all` | `articleid`、`emoji_type` (1=讚, 2~8=其他表情)、`action_type`、`event_date` | `WHERE appid=<app> AND event_date >= '<from>'` |
| 打賞事件 | `trans_donate_record_all` | `articleid`、`memberid` (donor)、`values` (P 幣金額)、`event_date` | `WHERE appid=<app> AND event_date >= '<from>'` |

### ⚠️ **別用**（停更，會回 0 或舊資料）

`trans_author_follower_statistics`（停 2025-08）/ `trans_article_view_statistics`（停 2025-12）/ `trans_forum_comment` / `trans_forum_reaction` / `trans_forum_donate`（停 2026-03-04）/ `trans_comment_latest` / `trans_reaction_latest`（停 2025-07）/ `trans_forum_article_create`（停 2025-08，用 `trans_forum_articles` 取代）。

### 範例 SQL：抓某 user 全部 user-level 數據

先抓貼文時間範圍縮 `event_date` 掃描範圍：

```sql
SELECT MIN(createtime) min_t, MAX(createtime) max_t
FROM trans_forum_articles
WHERE creatorid='<user>' AND deleted=0
```

`createtime` 是 epoch ms 字串，`FROM_UNIXTIME(createtime/1000)` 轉日期；用最早日期當 `event_date` 起點。

然後一個 query 抓所有 per-post 互動：

```sql
WITH user_articles AS (
  SELECT CAST(articleid AS BIGINT) articleid, title, createtime
  FROM trans_forum_articles
  WHERE creatorid='<user>' AND deleted=0
),
reads AS (
  SELECT articleid, COUNT(*) views, COUNT(DISTINCT memberid) unique_viewers
  FROM trans_forum_article_reads
  WHERE event_date >= '<from>' AND event_name='Article_read'
  GROUP BY articleid
),
comments AS (
  SELECT articleid, SUM(CASE WHEN action_type=1 THEN 1 ELSE -1 END) cnt
  FROM trans_comment_record_all
  WHERE appid=<app> AND event_date >= '<from>'
  GROUP BY articleid
),
reactions AS (
  SELECT articleid, SUM(CASE WHEN action_type=1 THEN 1 ELSE -1 END) cnt
  FROM trans_reaction_record_all
  WHERE appid=<app> AND event_date >= '<from>'
  GROUP BY articleid
),
donates AS (
  SELECT articleid, COUNT(*) donor_cnt, SUM(values) pcoin
  FROM trans_donate_record_all
  WHERE appid=<app> AND event_date >= '<from>'
  GROUP BY articleid
)
SELECT a.articleid, a.title,
       COALESCE(rd.views,0) views, COALESCE(rd.unique_viewers,0) unique_viewers,
       COALESCE(c.cnt,0) comments, COALESCE(r.cnt,0) reactions,
       COALESCE(d.donor_cnt,0) donor_cnt, COALESCE(d.pcoin,0) pcoin
FROM user_articles a
LEFT JOIN reads rd ON a.articleid = rd.articleid
LEFT JOIN comments c ON a.articleid = c.articleid
LEFT JOIN reactions r ON a.articleid = r.articleid
LEFT JOIN donates d ON a.articleid = d.articleid
ORDER BY views DESC
```

追蹤者另外查（不依貼文）：

```sql
SELECT COUNT(*) followers FROM ext_forum_member_follow WHERE FollowMemberId = <user_int>
```

### 注意

- `creatorid` 在 `trans_forum_articles` 是 **string**；`FollowMemberId` 在 `ext_forum_member_follow` 是 **BIGINT**。別搞混型別。
- `trans_forum_article_reads` 的 `event_name` 有 `Article_read`（含 `view_type=articlePage` / `readMore`）和 `FRM_PostInnerPage_entered`。預設只取 `Article_read` 為「瀏覽」。要更窄就加 `view_type='articlePage'`。
- 留言/按讚/打賞要記得 `appid` filter，這些表是跨 app。
- 留言/按讚是 net count（create - delete）。

---

## 範例

### A. Anya — 註冊 dataset（「昨天理財寶 launch 次數」）

1. check token
2. `anya-schema.sh` → 找到 app_id=1 是理財寶，dataset_id=b065fc08，anya_table=ext_userbehavior_v2，event_name_col=object.eventName
3. `anya-events.sh b065fc08 1` → 確認 "launch" 存在
4. 生 SQL：
   ```sql
   SELECT COUNT(*) AS launches FROM ext_userbehavior_v2
   WHERE app_id = 1 AND object.eventName = 'launch' AND txDate = DATE '2026-05-06'
   ```
5. `anya-query.sh "$SQL" 10 b065fc08 1`
6. 回表格 + 後續建議

### B. Anya — OneLink（「過去 7 天 onelink `abc-123` 點擊數」）

1. 直接套 `trans_onelink_clickcounts`：
   ```sql
   SELECT click_date, SUM(click_counts) AS clicks
   FROM trans_onelink_clickcounts
   WHERE onelink = 'abc-123' AND click_date BETWEEN DATE '2026-04-30' AND DATE '2026-05-06'
   GROUP BY click_date ORDER BY click_date
   ```
2. `anya-query.sh "$SQL"`（dataset_id / app_id 留空）
3. 呈現趨勢表

### C. Anya — 未知 table 探索（「查一下訂閱購買的資料」）

1. `SHOW TABLES` → 用 LIKE 或人工從結果篩，找出含 "subscription" / "purchase" / "order" 的 table
2. 對候選 `DESCRIBE <table>` 看欄位
3. 必要時 `SELECT * FROM <table> LIMIT 5` 確認資料樣貌
4. 生正式 SQL 查
5. 呈現結果 + 提醒使用者這張表不在註冊 dataset，欄位是即時探索的

### D. GA4 — 「上週 Readmo Blog 的 page_view」

1. `ga4-properties.sh` → 拿 Blog property_id
2. `ga4-report.sh "<date_from>" "<date_to>" "page_view" "<blog_pid>"`
3. 回每日 page_view（含 device 拆分）

### E. GA4 AB — 「Mlytics_C vs Control 上週 CTR」

1. `ga4-properties.sh` → Forum property_id（discussions AB 通常在 Forum）
2. `ga4-ab-ctr.sh` 帶 groups JSON
3. 回 groups + CTR 數字

### F. GA4 flexible — 「過去七天 promptVariant=開關廣告_A 且 ad_visible=true 的 readmo_questions_clicked，依 articleId 聚合」

1. `ga4-properties.sh` → Forum (`258250306`)
2. `ga4-event-params.sh` / `ga4-param-values.sh` 確認 param 名稱與值
3. 含中文 filter 值，用 curl + body 檔（避免 shell UTF-8 問題）：
   ```bash
   TOKEN=$(jq -r '.access_token' "$HOME/.anya-skill/token.json")
   BODY=$(mktemp)
   jq -n '{
     date_from:"2026-04-30", date_to:"2026-05-06",
     event_names:["readmo_questions_clicked"],
     dimensions:["customEvent:articleId"],
     metrics:["eventCount"],
     dimension_filter:{
       "customEvent:promptVariant":["開關廣告_A"],
       "customEvent:related_questions_ad_visible":["true"]
     },
     property_id:"258250306"
   }' > "$BODY"
   curl -sS -X POST "https://franky.ailabdev.cc/api/skill/ga4/flexible-report" \
     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json; charset=utf-8" \
     --data-binary @"$BODY"
   rm -f "$BODY"
   ```
4. 回 row per articleId + eventCount。GA4 對高基數維度有 thresholding，總和會略低於 fixed-shape `/report` 的總量

---

## 錯誤處理

| HTTP | 意義 | 要做什麼 |
|---|---|---|
| 401 Unauthorized | token 失效 / 被撤銷 / 過期 | 提示使用者「token 已失效」並跑 `login.sh` |
| 400 `Safety: Only ... queries allowed` | SQL 被擋（不是 SELECT/WITH/SHOW/DESCRIBE/EXPLAIN） | 讀訊息、修正 SQL，重試至多 **2** 次 |
| 400 其他 Spark / GA4 錯誤 | SQL 語法錯 / 欄位不存在 / 資料型別錯 / GA4 invalid request | 讀錯誤訊息修正，重試至多 **2** 次；未知 Anya table 可先 `DESCRIBE` 看欄位 |
| 429 Rate limit exceeded | 觸達 60 req/min（**Anya + GA4 共桶**） | 停下來告訴使用者已達速率上限，等一分鐘 |
| 500 GA4 backend error | GA4 後端錯誤 | 顯示 detail，最多重試 1 次 |
| 502 Anya query failed | Anya 本身錯誤 | 顯示 detail，建議使用者重試或檢查 SQL |

**關鍵原則：** 錯誤時不要陷入 retry loop，最多 2 次修正就要停下來跟使用者說明問題。

---

## 安全與稽核

- 每次查詢都會被後端紀錄到 `usage_events` 表，feature 區分 `skill_query` (Anya) / `skill_ga4_query` (GA4)，含 `user_email`、`sql` 或 request body、`row_count`、`elapsed_ms`
- Anya + GA4 共用 60 req/min per-user rate limit
- 若使用者要求「擷取大量個資 / email / 手機號」，請先提醒這會進 audit log
