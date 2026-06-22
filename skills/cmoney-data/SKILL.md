---
name: cmoney-data
description: Anya + Readmo GA4 + Threads 整合查詢工具 — 用中文問題查 CMoney 內部使用者行為（Anya / Spark SQL）、Readmo Web 分析（GA4）與公司 Threads 帳號發文成效。OAuth 授權後 Claude Code 直接生 SQL、打 GA4 report、或查 Threads 帳號成效取資料，每次查詢都寫 audit log。適用於「昨天理財寶 launch 次數」「上週 Readmo Blog page_view」「Mlytics_C vs Control CTR 比較」「OneLink 點擊歸因」「某 Threads 帳號上週成效 / Top 貼文 / views 趨勢」等問題。
---

# CMoney 資料查詢 Skill (Anya + Readmo GA4 + Threads)

你（Claude Code）要幫使用者用中文問題查 CMoney 內部資料 — 涵蓋三個來源：
- **Anya**：使用者行為事件（SDK 埋點，Spark SQL）
- **Readmo GA4**：Readmo Web property（投資網誌 / 討論區 / 文章子網域）pageview / CTR / AB 測試
- **Threads**：公司經營的 Threads 帳號發文成效（views / likes / replies / followers / Top 貼文 / 逐日趨勢）

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
| Threads 帳號發文成效、views/likes/replies/followers、Top 貼文、發文/views 逐日趨勢 | Threads |
| 提到某個 Threads 帳號（@handle）、「我們的 Threads」、「小編帳號」成效 | Threads |
| 不確定 | 先列 GA4 properties + Anya schema 兩邊都看 |

---

## Anya 子流程

### 1. 拉路由索引（每次 session 第一次 Anya 查詢時執行）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/anya-schema.sh"
```

回傳 compact 索引（~24KB）：每個 dataset 只有 `id` / `app_id` / `display_name` / `type` / `has_extra_tables`，用來把使用者的問題對到 dataset。本地快取 1 小時（`~/.anya-skill/schema-cache.json`），同 session/近期重跑幾乎零延遲；懷疑 registry 剛更新時用 `anya-schema.sh refresh` 強制重抓。**註冊 dataset 是 hint，不是硬性限制 — 使用者也可以查任何其他 Anya 表，只是沒有預先整理好的 schema_text**。

對到 dataset 後，**只抓你要查的那一個的完整 schema**（~1.5KB，含 `anya_table` / `event_name_col` / `schema_text` / `extra_tables`）：

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/anya-dataset.sh" <dataset_id>
```

（`anya-schema.sh full` 仍可拿舊版全量 registry ~360KB，但會撐爆工具輸出上限被截斷存檔，除非真的需要一次看所有 schema_text，否則不要用。）

### 2. 判斷查哪張表

分三種情況處理：

#### A. 問題對應到註冊 dataset（最常見）

例如「理財寶 launch 次數」→ 索引裡 `display_name` 含「理財寶」→ `anya-dataset.sh <id>` 拿 schema。
- 用 dataset 的 `anya_table` + `schema_text` 產生 SQL
- 跑 `anya-events.sh <dataset_id> <app_id>` 確認事件名稱存在（與 anya-dataset.sh 互相獨立，可同一則訊息平行跑）

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

### 0. Readmo 常用事件速查（查 Readmo 前先看這個，多數情況免現查）

> 通常不用再跑 `ga4-event-params.sh` / `ga4-param-values.sh` 探索。核心事件 2026-06-22 在 Blog 471029047 live 確認在打；aigc/Mlytics 事件實測也只在 Blog 471029047。

**Property 對照**

| 站別 | property_id | 備註 |
|---|---|---|
| Blog 投資網誌 | `471029047` | `cmnews.com.tw/article/*`；Readmo AB 主戰場，aigc/Mlytics 也在這 |
| Forum 討論區 | `258250306` | 同學會家族 forum 文章 |
| Readmo 文章子網域 | `505661605` | `readmo.cmoney.tw`；**沒有** `question_prompt_ver` 維度 |
| WordPress Plugin | `515598585` | 一個 property 裝所有外站；事件名與上面不同（見下） |

**CTR 標準（重要，別搞錯點擊事件）**

- Readmo 延伸問題 **CTR = `readmo_questions_clicked_without_page_lo` ÷ `readmo_questions_viewed`**，view ↔ click 用 `customEvent:articleId` 關聯。
- **點擊標準事件 = `readmo_questions_clicked_without_page_lo`**：用戶一點就 fire、定義比照 aigc。GA4 事件名 40 字上限，原名 `readmo_questions_clicked_without_page_loaded` 被截斷，查詢一律用截斷版。
- `readmo_questions_clicked` 是更嚴格定義的舊 click，**目前不作為 CTR 標準**，除非使用者特別指定。
- **問「Mlytics」數據 → 查 `aigc_question_clicked` + `aigc_question_impression`**（都在 Blog `471029047`），CTR = clicked ÷ impression。

**事件清單**

| 事件名 | property | 用途 |
|---|---|---|
| `page_view` | Blog/Forum/子網域 | 真實文章瀏覽（PV，跟點擊差 10x，別混用） |
| `readmo_questions_viewed` | Blog/Forum/子網域 | 延伸問題曝光 → CTR 分母 |
| `readmo_questions_clicked_without_page_lo` | Blog/Forum | ✅ 目前點擊標準 → CTR 分子 |
| `readmo_questions_clicked` | Blog/Forum/子網域 | 舊嚴格 click，**非** CTR 標準 |
| `aigc_question_impression` | Blog `471029047` | **Mlytics** 曝光 → CTR 分母 |
| `aigc_question_clicked` | Blog `471029047` | **Mlytics** 點擊 → CTR 分子 |
| `section_view` / `question_click` | WP Plugin `515598585` | 外站 plugin 曝光/點擊；CTR = `question_click` ÷ `section_view` |

**點擊事件的 param**

`readmo_questions_clicked_without_page_lo`：
- `isAds` — 該點擊是否為廣告
- `position` — 標題展示順序
- `click_url` — 點擊跳轉連結
- `click_text` — 標題文案
- `usedModelKey` — 使用的模型
- `promptVariant` — AB 變體（見下）

`aigc_question_clicked`（Mlytics）param 同義：`click_text` / `click_url` / `position`。

**算 CTR / AB 的陷阱**

- **view ↔ click 關聯用 `articleId`**（最穩）。`customEvent:articleId` 各 property 格式不同：**Blog** = `<slug>-<UUID>`、**Forum** = 純數字（含 `-`/字母→Blog、純數字→Forum）。
- **AB 變體名掛在不同 custom dimension**（用單一 param filter 會撈到 0）：`readmo_questions_viewed` → `customEvent:question_prompt_ver`；click 系列（`_without_page_lo`/`readmo_questions_clicked`）→ `customEvent:promptVariant`（另一個為空）。子網域沒有 `question_prompt_ver`。
- **廣告 click 不帶實驗變體**（promptVariant 是廣告系統值如 `AdQuestionGeneration_v3_System`），要歸因 A/B 用 `articleId` 橋接（A 組 view 的 articleId 集合 ↔ 廣告 click 的 articleId）。
- 業配文 AB（2026-06 起）promptVariant 三層：帶分組名(`SponsorTitle_A`/`AdQuestionTitle_A`)=整個 widget 5 題點擊（~9.5%，非單卡）；單卡廣告=`AdQuestionGeneration_v5_Tenant`、單卡業配=`SponsoredQuestionGeneration_v8_Tenant`（真單卡 CTR ~1%）。
- 變體剛上線當天 intraday 約 4–12h 才撈得到、Realtime UI 看得到 ≠ Data API；隔天最穩，並避開最近 24–48h GA4 freshness window。
- WP plugin 篩選維度：`customEvent:client_id`=安裝站、`hostName`=真 domain（GA4 把 `page_location` 標成「Domain」其實是文章完整 URL）。

### 1. 列出可用 property

列**全部**可存取的 property（≈58，含 registry 友善名；問到「全部 CMoney 網站」用這支）：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-all-properties.sh"
```
回 `{total, properties:[{id, display_name, account, hidden, order}]}`。用 `display_name` 把使用者口語站名對到 id（如「CMoney 全網」→ `258236863`、「投資網誌」→ `471029047`、「同學會」→ `258250306`）。

只需要 Blog/Forum/Readmo 這組精選子集時，仍可用舊的：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-properties.sh"
```

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
  [metrics_csv] [property_id] [dimension_filter_json] [order_by] [limit]
```
- `dimensions_csv`：用 CSV，custom event 維度寫成 `customEvent:<param_name>`，內建維度直接寫名（如 `date`, `deviceCategory`）
- `metrics_csv`：預設 `eventCount`
- `dimension_filter_json`：filter key 也是 GA4 dim 名（custom 維度同樣加 `customEvent:` 前綴）
- `order_by` + `limit`：server-side 排序（預設降冪）+ 截斷。**問「前 N 名 / top N / 最多」時務必帶**——高基數維度（pageLocation 等）全量可達數十萬列 / 87MB / 47 秒，top-5 只要 5 列 / 5 秒。例：
  ```bash
  # 投資網誌 7 天瀏覽 top 5 頁
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-flexible-report.sh" \
    2026-06-02 2026-06-08 page_view pageLocation eventCount 471029047 null eventCount 5
  ```
  不帶 = 原本全量分頁行為（要全部資料做本地後處理時用，如全站作者統計）。

什麼時候用：要按 articleId / page_title / 任意 custom 維度做 group by，或要 filter 多個 custom param 後算總量。
含中文 filter 值時改用 curl + body 檔（範例見「範例 F」）。

**E. 跨 property 流量比較（單一 metric，可算成長率）**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-compare-properties.sh" \
  "<metric>" "<date_from>" "<date_to>" [compare_from] [compare_to] [property_ids_csv]
```
- `metric`：`sessions`（預設語意的「流量」）/ `activeUsers` / `screenPageViews` / `eventCount`
- 給 `compare_from`/`compare_to` 才會算 `growth_pct`；`property_ids_csv` 省略 = 全部可見 property
- 後端平行 fan-out 數十個 property，回 `{metric, total, properties:[{id, display_name, value, compare_value, growth_pct}]}` 依成長排序

#### Cookbook：跨 property 流量成長歸因（「哪個站近期成長最多、為什麼」）
1. `ga4-all-properties.sh` → 確認站別與 id
2. `ga4-compare-properties.sh sessions <近期from> <近期to> <前期from> <前期to>` → 找成長最多的站（**過濾掉 value 很小的雜訊站**，例如 sessions < 數百的不看）
3. 對該站用 `ga4-flexible-report.sh`（`metric=sessions`）拆歸因維度找成長來源：
   - 渠道 `sessionDefaultChannelGroup`（Organic Search / Direct / Referral…）
   - 來源 `sessionSource` / `sessionMedium`、入口頁 `landingPage`、地區 `country`、裝置 `deviceCategory`
4. 總結：哪個站 + 成長幅度 + 主要歸因來源

### 4. 呈現

- markdown 表格
- 結果多就只顯示 top 20 + 註明總筆數
- 後續建議：要不要拆 device、看趨勢、加 publish date filter 等

---

## GSC（Google Search Console）子流程

何時用：問到某站在 Google 搜尋的 **clicks / impressions / CTR / 排名（position）**、Discover / Google News 成效、或哪個帳號的搜尋成效。資料分 web / discover / googleNews / news / all 五個 surface。

### 1. 列出可查的 GSC 站
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gsc-sites.sh"
```
回 `{sites:[{site_url, permission_level}]}`。目前 SA 可存取：`https://aigc.readmo.ai/`、`sc-domain:cmnews.com.tw`、`sc-domain:readmo.cmoney.tw`。

### 2. 站台層成效
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gsc-site.sh" "<date_from>" "<date_to>" [site_url]
```
`site_url` 省略 = 後端預設（`sc-domain:cmnews.com.tw`）。回各 surface 的 `{clicks, impressions, ctr, position}`（web/discover 另含 click_share / impression_share）。

### 3. 帳號層成效（per-account 拆分）
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gsc-account.sh" "<date_from>" "<date_to>" [user_ids_csv] [top_n]
```
不給 `user_ids` = 全站 aggregate（`by_account` 空）；給 `user_ids` = 逐帳號拆分（`top_n` 限筆數）。

### 4. 每篇文章層成效（per-URL / per-article）
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gsc-account-pages.sh" "<date_from>" "<date_to>" "<user_ids_csv>" [surfaces_csv] [site_url] [min_impressions] [top_n_per_account]
```
`user_ids` 必填。回 `by_account:[{user_id, page_count, pages:[{url, surfaces:{web/discover…:{clicks,impressions,ctr,position}}, all:{…}}]}]`。`surfaces` 預設 `web,discover`；`min_impressions` 過濾雜訊；`top_n_per_account` 限每作者篇數（0=不限）。pages 依 `all.impressions` 由高到低排。
- **有曝光文章數**（per author per surface）= 數 `pages` 裡該 surface `impressions > 0` 的篇數
- **曝光率** = 有曝光文章數 ÷ 發文數（發文數另從 Anya / GA4 取）
- 「哪幾篇帶搜尋流量」= 依 `all.clicks` 排序；「indexed 但沒人搜」= `impressions` 高而 `clicks` ≈ 0

### 5. 彈性維度拆分（per-query / per-country / per-device / 逐日）
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/gsc-breakdown.sh" "<date_from>" "<date_to>" "<dimensions_csv>" [surfaces_csv] [user_ids_csv] [site_url] [min_impressions] [top_n]
```
`dimensions` 是 `date,query,page,country,device` 的子集。回 `rows:[{keys:{<dim>:value}, surfaces:{…}, all:{…}}]`；給 `user_ids` 則改回 `by_account:[{user_id,row_count,rows:[…]}]`（作者歸因）。

| 想知道 | dimensions | 備註 |
|---|---|---|
| 哪些搜尋字帶量 | `query` | **只有 web surface**（discover/news 無 query，後端自動跳過該 surface） |
| 流量地區拆分 | `country` | 回 3 碼國碼（twn / usa…） |
| 裝置拆分 | `device` | MOBILE / DESKTOP / TABLET |
| 逐日趨勢 | `date` | 每天一列；可配 `query` / `page` 做逐日細分 |
| 全站逐頁 | `page` | 不給 user_ids = 全站；給 user_ids = 逐作者 |
| 交叉 | 例 `date,query` | 多維度組合 |

`surfaces` 預設 `web`（`query` 維度只有 web 有）。GA Explorer 的 in-app AI chat 也有對應的 `gsc_account_pages` / `gsc_breakdown` 工具。

注意：GSC 資料通常延遲約 2–3 天，查最近日期可能為 0 或不完整。

---

## Threads 子流程

查公司經營的 Threads 帳號發文成效。資料來自 Threads Graph API（後端用 `credentials/threads.json` 內的帳號 token 代查），每帳號結果有 60 秒 TTL cache。日期一律 `YYYY-MM-DD`。

> ⚠️ **`date_to` 一定要拉到「今天」（或最近一兩天）**。Threads 貼文/互動集中在近期，若 `date_to` 設太舊會錯過最近貼文，導致 `views`/`total_posts` 看起來是 0、帳號被誤判 `is_restricted=true`。使用者說「最近成效」「上週」時，`date_to` 用今天日期（從 Claude Code 環境取），不要停在幾天前。看到某帳號全 0 時，先確認區間有沒有涵蓋到今天再下結論。

### 1. 先列出有哪些帳號（使用者沒指名帳號時必做）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/threads-accounts.sh"
```

回 `{accounts:[{username}]}`。**後端沒設定 threads 憑證時回空陣列 `{accounts:[]}`（不是錯誤）** — 這時告訴使用者「Threads 整合尚未設定」即可，別硬查其他端點。其他三個端點在沒憑證時會回 503 `threads_not_configured`。

使用者若已指名帳號（@handle），可跳過這步直接查；但帳號名要對得上 `accounts` 清單。

### 2. 帳號彙總成效（最常用）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/threads-account-metrics.sh" "<usernames_csv>" "<date_from>" "<date_to>"
```

`usernames_csv` 逗號分隔（例 `accountA,accountB`）。回每帳號區間彙總：

| 欄位 | 意義 |
|---|---|
| `views` | 區間內總瀏覽（daily series 加總） |
| `likes` / `replies` / `reposts` / `quotes` | 區間互動總數 |
| `followers_count` | 目前追蹤者數（**< 100 fol 的帳號 Threads 政策不給數據，會回 0**） |
| `total_posts` | 區間內發文數 |
| `avg_views_per_post` / `avg_likes_per_post` / `avg_replies_per_post` | 每篇平均（`total_posts=0` 時為 null） |
| `is_restricted` | **true = 區間內 0 篇貼文但仍有 views** → 帳號可能被風控/降權，呈現時要標註提醒 |

### 3. Top 貼文

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/threads-top-posts.sh" "<usernames_csv>" "<date_from>" "<date_to>" [limit]
```

`limit` 預設 10、硬上限 50。依 `views` 由高到低排。每篇有 `post_id` / `text` / `permalink` / `timestamp` / `views` / `likes` / `replies` / `reposts` / `quotes` / `shares`（`shares` 只有貼文層級才有，帳號彙總沒有）。

### 4. 單一帳號逐日趨勢

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/threads-account-trend.sh" "<username>" "<date_from>" "<date_to>" [metric]
```

`metric`：`views`(預設) / `likes` / `replies` / `reposts` / `quotes`（**不支援 followers**）。回 `points:[{username,date,value}]`，逐日一筆。

### 5. 呈現

- markdown 表格；多帳號比較用一列一帳號
- `is_restricted=true` 的帳號明確標註「可能被風控（0 發文仍有流量）」
- `followers_count=0` 且帳號其實有人追蹤時，提醒「< 100 fol Threads 不給數據」
- 趨勢資料適合畫折線；後續建議：要不要看其他 metric、拉長區間、比較其他帳號

---

## Cookbook：投資網誌「作者文章瀏覽數」

「投資網誌某作者在某段時間的文章瀏覽數」、「全站作者 baseline 比較」用這個流程。

### 投資網誌 = `cmnews.com.tw/article/*`

- Property：Blog `471029047`
- URL 形式：`https://cmnews.com.tw/article/<authorSlug>-<uuid>`（**不在 blog.cmoney.tw**）
- 不要用 article-ctr 回的 `clicks` 當「瀏覽」— 那是 Readmo card click，跟真實 page_view 差 10x 以上

### 一招撈完：`ga4-flexible-report` + `pageLocation` 維度

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-flexible-report.sh" \
  "<date_from>" "<date_to>" "page_view" "pageLocation" "eventCount" "471029047"
```
單次 call 拿全站逐頁瀏覽。後處理（本地 Python）：

```python
import re
slug = lambda url: re.search(r'/article/([a-z0-9_]+)-[0-9a-f]', url).group(1)
art = [r for r in data['data'] if '/article/' in r['pageLocation']]
from collections import defaultdict
per_author = defaultdict(lambda: {'n':0,'pv':0})
for r in art:
    s = slug(r['pageLocation'])
    if s:
        per_author[s]['n'] += 1
        per_author[s]['pv'] += int(r['eventCount'])
```

### 「全站」三種定義，結論完全不同

| 定義 | 撈法 | 樣本量（3 天範例） | 適用情境 |
|---|---|---:|---|
| Readmo 投放池 | `ga4-article-ctr.sh ... readmo` 抓 URL | 7,145 篇 | 跟 Readmo 投放作者比效率 |
| Mlytics 投放池 | `ga4-article-ctr.sh ... mlytics` | 6,244 篇 | 跟 Mlytics 投放比 |
| **真正全站** | `ga4-flexible-report` + pageLocation × page_view 抓所有 `/article/*` | **77,113 篇 / 29,599 位作者** | 跟「平台所有作者」比，給管理層看 |

「真正全站 29,599 位作者」分母 = window 內**有文章被點過 ≥ 1 次**的作者數，不是「所有曾經發過文的作者」。報告 footer 要寫清楚。

### 流量來源分析（找出文章為什麼有人看）

```bash
FILTER='{"pageLocation":["<url>"]}'  # 或多個 URL
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ga4-flexible-report.sh" \
  "<date_from>" "<date_to>" "page_view" \
  "sessionDefaultChannelGroup" "eventCount" "<property_id>" "$FILTER"
# 更細：dimensions 改 "sessionSource,sessionMedium"
```

**重要發現（投資網誌 2026-05-11~13 5 篇 top view 文）**：
- 平均 **82% 流量來自 Google Organic**，Readmo card click ≤ 1%
- Readmo 投放的真正貢獻是「讓 Google 索引到 → SEO 帶量」，不是 card 點擊
- 做帶量歸因時不要把 Readmo card 當主要來源
- 想驗證單篇文章為什麼爆 → 一定要拉 channel 分佈

### 注意

- pageLocation 是 GA4 built-in **dimension**（駝峰）；filter key 用 `pageLocation`、不是 `page_location`
- `pageLocation` 含 query string、`pagePath` 只到 path — 別搞混
- article-ctr 的 `publish_date_from/to` 會排除「window 內被讀但發文早於 window」的舊文。要「window 內被讀的所有文章」用 flexible-report 不要 filter publish date
- flexible-report 維度高基數時 GA4 會 thresholding（極少數列被丟掉），總和略低於 fixed report

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

### ⚠️ 資料新鮮度陷阱（撈當天數據必看）

1. **`kafka_event_date` 分區有 lag**
   今天剛發的文，當天的 partition 不一定完整 — 跑 `kafka_event_date = '2026-05-13'` 可能漏掉 5/13 早上發、partition 還沒寫滿的文。
   **解法**：`kafka_event_date >= DATE '<from-2天>' AND kafka_event_date <= DATE '<to+1天>'`，再用 `createtime` (epoch ms) 在 application 端過濾到精確時窗。實測過案例：5/13 早上 5 個帳號剛發的文，用窄分區 (5/11~5/13) 完全漏掉、用寬分區 (5/8~5/14) 才撈到。

2. **`ext_forum_member_follow` 是分析 pipeline，非 live**
   表是離線同步（觀察為數小時到 1 天 lag）。對 follower 敏感的報告：
   - 數字會比 live 低 — 如某帳號線上顯示 6 但表內 4
   - footer 要註記「follower 為分析 pipeline 數據、非即時」
   - 對於 0/1/2 fol 這種小數，誤差比例大；對 ≥10 fol 的影響相對小

### 「全站排名」分母 caveat

報「全站 X 位作者 / 排 #Y」時，X 的定義很重要：

| 描述 | 真實意思 | SQL |
|---|---|---|
| 「全站 449,380 位作者」 | **至少 1 個追蹤者**的作者數 | `SELECT FollowMemberId, COUNT(*) FROM ext_forum_member_follow GROUP BY ...`；沒人追蹤的 0-follower 帳號不會出現在 follow 表 |
| 「全站 X 篇文章中排 #Y」 | window 內**有發文且有被讀**的篇數 | 上面 user-level 範例 SQL 的 reads JOIN 結果 |
| 「全站 N 位作者中排 #M」（per-post avg view） | window 內**有文章被讀**的作者數 | distinct slug from articles with views |

報告 footer 要明確標註定義，避免被誤解為「全部帳號」。

---

## 範例

### A. Anya — 註冊 dataset（「昨天理財寶 launch 次數」）

1. check token
2. `anya-schema.sh`（compact 索引）→ display_name「理財寶網頁版」對到 dataset_id=b065fc08, app_id=1
3. **同一則訊息平行跑**：`anya-dataset.sh b065fc08`（→ anya_table=ext_userbehavior_v2, event_name_col=object.eventName）+ `anya-events.sh b065fc08 1`（→ 確認 "launch" 存在）
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

### G. Threads — 「我們的 Threads 帳號上週成效」

1. `threads-accounts.sh` → 拿到帳號清單（使用者沒指名時）
2. `threads-account-metrics.sh "accountA,accountB" "2026-05-12" "2026-05-18"`
3. 回每帳號 views/likes/followers/total_posts 表；`is_restricted=true` 的標註提醒

### H. Threads — 「accountA 上週哪幾篇最紅 + views 趨勢」

1. `threads-top-posts.sh "accountA" "2026-05-12" "2026-05-18" 5` → Top 5 貼文（permalink + views）
2. `threads-account-trend.sh "accountA" "2026-05-12" "2026-05-18" "views"` → 逐日 views 折線

---

## 錯誤處理

| HTTP | 意義 | 要做什麼 |
|---|---|---|
| 401 Unauthorized | token 失效 / 被撤銷 / 過期 | 提示使用者「token 已失效」並跑 `login.sh` |
| 400 `Safety: Only ... queries allowed` | SQL 被擋（不是 SELECT/WITH/SHOW/DESCRIBE/EXPLAIN） | 讀訊息、修正 SQL，重試至多 **2** 次 |
| 400 其他 Spark / GA4 錯誤 | SQL 語法錯 / 欄位不存在 / 資料型別錯 / GA4 invalid request | 讀錯誤訊息修正，重試至多 **2** 次；未知 Anya table 可先 `DESCRIBE` 看欄位 |
| 429 Rate limit exceeded | 觸達 60 req/min（**Anya + GA4 + Threads 共桶**） | 停下來告訴使用者已達速率上限，等一分鐘 |
| 500 GA4 backend error | GA4 後端錯誤 | 顯示 detail，最多重試 1 次 |
| 502 Anya query failed | Anya 本身錯誤 | 顯示 detail，建議使用者重試或檢查 SQL |
| 503 `threads_not_configured` | 後端沒設定 Threads 憑證 | 告訴使用者「Threads 整合尚未設定」，不要重試 |
| 422（Threads） | username/date 格式錯、date_from>date_to、metric 不支援 | 修正參數重試 |

**關鍵原則：** 錯誤時不要陷入 retry loop，最多 2 次修正就要停下來跟使用者說明問題。

---

## 安全與稽核

- 每次查詢都會被後端紀錄到 `usage_events` 表，feature 區分 `skill_query` (Anya) / `skill_ga4_query` (GA4) / `skill_threads_query` (Threads)，含 `user_email`、`sql` 或 request body、`row_count`、`elapsed_ms`
- Anya + GA4 + Threads 共用 60 req/min per-user rate limit
- 若使用者要求「擷取大量個資 / email / 手機號」，請先提醒這會進 audit log
