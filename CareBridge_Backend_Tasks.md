# CareBridge 照護橋 — 後端開發工作清單

> **負責範圍**: Server API + 資料庫 + AI 整合 + 推播 + 部署
> **技術棧**: Swift (Vapor) + PostgreSQL + Redis + AWS S3
> **最後更新**: 2026/04/11

---

## Phase 1：專案初始化與基礎建設

### 1.1 Vapor 專案建立

- [ ] 使用 `vapor new CareBridgeAPI` 初始化專案
- [ ] 設定專案結構：

```
CareBridgeAPI/
├── Package.swift                # 依賴管理
├── Sources/
│   └── App/
│       ├── configure.swift      # App 設定（DB、Redis、Middleware）
│       ├── routes.swift         # 路由總入口
│       ├── Controllers/         # 各模組 Controller
│       │   ├── AuthController.swift
│       │   ├── FamilyController.swift
│       │   ├── ChatController.swift
│       │   ├── BoardController.swift
│       │   ├── ExpenseController.swift
│       │   ├── LeaveController.swift
│       │   ├── CareLogController.swift
│       │   ├── MedicationController.swift
│       │   ├── HealthController.swift
│       │   ├── EventController.swift
│       │   ├── TodoController.swift
│       │   ├── DocumentController.swift
│       │   ├── AIController.swift
│       │   ├── SOSController.swift
│       │   └── NotificationController.swift
│       ├── Models/              # Fluent ORM Model
│       │   ├── User.swift
│       │   ├── Family.swift
│       │   ├── Chat.swift
│       │   ├── Message.swift
│       │   ├── BoardRequest.swift
│       │   ├── Expense.swift
│       │   ├── Leave.swift
│       │   ├── CareLog.swift
│       │   ├── Medication.swift
│       │   ├── MedicationConfirmation.swift
│       │   ├── HealthData.swift
│       │   ├── HealthAlert.swift
│       │   ├── Event.swift
│       │   ├── Todo.swift
│       │   ├── Document.swift
│       │   ├── Notification.swift
│       │   ├── Device.swift
│       │   ├── AIConversation.swift
│       │   └── SOSRecord.swift
│       ├── Migrations/          # DB Migration
│       ├── Middleware/           # JWT 驗證、角色權限、Rate Limiting
│       ├── DTOs/                # Request / Response DTO
│       ├── Services/            # 業務邏輯服務
│       │   ├── TranslationService.swift
│       │   ├── APNsService.swift
│       │   ├── S3Service.swift
│       │   ├── AIService.swift
│       │   ├── OCRService.swift
│       │   └── RAGService.swift
│       └── WebSocket/           # WebSocket 處理
├── Tests/
├── Docker/
│   ├── Dockerfile
│   └── docker-compose.yml       # API + PostgreSQL + Redis
└── Resources/
    └── first-aid-docs/          # RAG 用急救文件
```

- [ ] 設定 `Package.swift` 依賴：
  - `vapor/vapor`
  - `vapor/fluent`
  - `vapor/fluent-postgres-driver`
  - `vapor/jwt`
  - `vapor/redis`
  - `soto-project/soto` (AWS S3 SDK for Swift)

### 1.2 Docker 本地開發環境

- [ ] 撰寫 `Dockerfile`（Swift 6.x + Vapor）
- [ ] 撰寫 `docker-compose.yml`：
  - Vapor API Server（port 8080）
  - PostgreSQL 16（port 5432）+ pgvector 擴展
  - Redis 7（port 6379）
- [ ] 環境變數管理（`.env` 檔案，含 DB 連線、JWT Secret、S3 Key、Claude API Key）

### 1.3 資料庫 Schema 與 Migration

- [ ] 建立所有 Fluent Model（對應 API 文件附錄的 18 張資料表）
- [ ] 撰寫 Migration 檔案（逐版本建立 schema）
- [ ] 啟用 pgvector 擴展（`CREATE EXTENSION vector`）
- [ ] 建立必要的 Index：
  - `users.email`（唯一索引）
  - `health_data(family_id, type, recorded_at)`（複合索引）
  - `care_logs(family_id, timestamp)`
  - `messages(chat_id, sent_at)`
  - `notifications(user_id, read, created_at)`

### 1.4 通用中介層（Middleware）

- [ ] **JWT 驗證 Middleware**：驗證 Bearer Token，注入 `req.auth` 使用者資訊
- [ ] **角色權限 Middleware**：依 API 端點限制角色存取（對照 API 文件的角色權限矩陣）
- [ ] **Rate Limiting Middleware**：基於 Redis 的請求頻率限制
- [ ] **統一錯誤處理**：所有錯誤回應格式統一為 `{ success: false, error: { code, message, details } }`
- [ ] **CORS Middleware**：允許前端跨域存取（開發環境）

---

## Phase 2：認證與使用者管理

### 2.1 認證 API（功能 1.1–1.8）

- [ ] `POST /auth/register` — 註冊
  - 密碼 bcrypt 雜湊
  - 產生 JWT Access Token（1 小時）+ Refresh Token（30 天）
  - Email 唯一性驗證
- [ ] `POST /auth/login` — 登入
- [ ] `POST /auth/refresh` — Token 刷新
  - 舊 Refresh Token 加入 Redis 黑名單
  - 產生新 Token pair
- [ ] `GET /auth/me` — 取得個人資訊
- [ ] `POST /auth/forgot-password` — 寄送密碼重設信
  - 產生有時效的重設 Token（存 Redis，15 分鐘過期）
  - 整合 Email 發送服務（SMTP / AWS SES）
- [ ] `POST /auth/reset-password` — 重設密碼
- [ ] `DELETE /auth/account` — 刪除帳號（級聯刪除所有相關資料）
- [ ] `PUT /users/:id` — 更新個人資訊

### 2.2 家庭管理 API（功能 2.1–2.4）

- [ ] `POST /families` — 建立家庭群組
  - 自動產生 8 位邀請碼（唯一性檢查）
  - 建立者自動加入為 primary family_member
- [ ] `GET /families/:id` — 取得家庭資訊 + 成員列表
- [ ] `POST /families/:id/members` — 透過邀請碼加入
- [ ] `DELETE /families/:id/members/:userId` — 移除成員

---

## Phase 3：即時通訊

### 3.1 聊天 REST API（功能 4.1–4.7）

- [ ] `GET /chats` — 聊天室列表（含未讀計數，從 Redis 讀取）
- [ ] `POST /chats` — 建立聊天室（group / direct）
- [ ] `GET /chats/:id/messages` — 歷史訊息（cursor-based 分頁）
- [ ] `POST /chats/:id/messages` — 發送訊息（HTTP fallback）
  - 文字訊息：呼叫翻譯服務 → 存入翻譯結果
  - 圖片訊息：上傳 S3 → 儲存 URL

### 3.2 WebSocket 即時通訊

- [ ] `WS /ws/chat/:id` — WebSocket 連線管理
  - Token 驗證（query parameter）
  - 連線池管理（Redis pub/sub 支援多 server 實例）
  - 事件處理：
    - `message`：接收訊息 → 翻譯 → 廣播給聊天室成員
    - `typing`：轉發「正在輸入」狀態
    - `read`：已讀回執
- [ ] 離線訊息處理：WebSocket 斷線時改用 APNs 推播

### 3.3 翻譯服務（功能 3.2–3.3）

- [ ] `POST /translate` — 文字翻譯
- [ ] `POST /translate/speech` — 語音轉文字 + 翻譯
  - 接收音訊檔案 → 呼叫 Speech-to-Text → 翻譯
- [ ] 翻譯服務整合：
  - 優先使用輕量翻譯模型或翻譯 API
  - 複雜內容 fallback 到 Claude API
- [ ] 翻譯快取（Redis）：相同文字+語言對不重複翻譯

---

## Phase 4：照護核心 API

### 4.1 照護日誌 API（功能 6.1–6.7）

- [ ] `GET /care-logs` — 時間軸查詢（支援類型篩選、日期區間、分頁）
- [ ] `POST /care-logs` — 新增紀錄
  - 支援 5 種類型：medication / vital / meal / activity / note
  - 照片附件上傳至 S3
  - 文字內容自動翻譯
- [ ] `PUT /care-logs/:id` — 更新紀錄
- [ ] `GET /care-logs/summary` — 照護摘要（供 AI Agent 使用）
  - 計算用藥順從度、生理平均值、飲食統計、活動統計

### 4.2 用藥管理 API（功能 7.1–7.6）

- [ ] `GET /medications` — 藥物清單
- [ ] `POST /medications` — 新增藥物
  - 自動翻譯藥物名稱與說明
  - 建立用藥提醒排程（寫入 events 表，type: medication）
- [ ] `PUT /medications/:id` — 更新藥物
- [ ] `POST /medications/:id/confirm` — 餵藥拍照確認
  - 照片上傳 S3
  - **自動建立 care_logs 用藥紀錄**（跨模組連動）
  - 推播通知家屬
- [ ] 用藥提醒排程（Cron Job 或 Vapor Queues）：
  - 定時檢查待服藥項目 → 推播通知看護 + Watch

### 4.3 健康監測 API（功能 10.1–10.8）

- [ ] `POST /health/sync` — Watch 健康數據批次同步
  - 去重處理（同一 timestamp 不重複寫入）
  - **即時異常檢測**：比對閾值 → 觸發警示
  - 異常時自動推播通知所有家庭成員
- [ ] `GET /health/data` — 歷史數據查詢
  - 支援 `raw` / `hourly` / `daily` 聚合模式
  - SQL 聚合查詢最佳化
- [ ] `GET /health/dashboard` — 儀表板彙總
  - 最新數值 + 今日摘要 + 週趨勢 + 閾值設定
- [ ] `GET /health/alerts` — 異常警示紀錄
- [ ] `PUT /health/alerts/:id/acknowledge` — 確認警示
- [ ] `PUT /health/thresholds` — 更新異常閾值

### 4.4 消費記帳 API（功能 8.1–8.5）

- [ ] `POST /expenses/scan` — 收據 OCR（非同步處理）
  - 接收收據照片 → 上傳 S3
  - 回應 202 Accepted
  - 背景任務：Vision OCR 文字擷取 → Claude API 結構化解析 → 儲存結果
  - 完成後推播通知前端
- [ ] `GET /expenses/:id` — 取得單筆消費紀錄
- [ ] `GET /expenses` — 消費紀錄列表（日期/分類篩選）
- [ ] `PUT /expenses/:id` — 修正 OCR 結果
- [ ] `GET /expenses/monthly` — 月結帳單
  - SQL 聚合：總支出、分類佔比、每日趨勢、常去商店排行

---

## Phase 5：輔助功能 API

### 5.1 留言板 API（功能 5.1–5.4）

- [ ] `GET /boards/requests` — 需求列表（狀態篩選）
- [ ] `POST /boards/requests` — 新增需求
  - 品項名稱自動翻譯
  - 推播通知家屬
- [ ] `PUT /boards/requests/:id` — 確認/駁回
  - 推播通知看護

### 5.2 請假管理 API（功能 9.1–9.4）

- [ ] `POST /leaves` — 請假申請
  - 請假原因自動翻譯
  - 推播通知家屬
- [ ] `GET /leaves` — 請假紀錄列表
- [ ] `PUT /leaves/:id` — 核准/駁回
  - 核准後**自動建立 events 行事曆事件**（跨模組連動）
  - 推播通知看護

### 5.3 行事曆 + 代辦 API（功能 11–12）

- [ ] `GET /events` — 行程列表（日期區間查詢）
- [ ] `POST /events` — 新增行程
  - 標題自動翻譯
- [ ] `PUT /events/:id` — 更新行程
- [ ] `DELETE /events/:id` — 刪除行程
- [ ] `GET /todos` — 代辦列表
- [ ] `POST /todos` — 新增代辦
  - 推播通知被指派者
- [ ] `PUT /todos/:id` — 更新/完成代辦
  - 完成時**自動建立 care_logs 活動紀錄**（跨模組連動）
- [ ] 行程提醒排程（Cron Job）：行程前 N 分鐘推播

### 5.4 文件管理 API（功能 13.1–13.4）

- [ ] `POST /documents` — 上傳文件（multipart → S3）
  - 檔案大小限制 10MB
  - 支援 PDF/JPG/PNG
- [ ] `GET /documents` — 文件列表（分類篩選）
- [ ] `GET /documents/:id` — 取得 Presigned URL（1 小時時效）
- [ ] `DELETE /documents/:id` — 刪除文件（DB + S3）

---

## Phase 6：AI 功能整合

### 6.1 AI 智慧助理（功能 14.1–14.6）

- [ ] `POST /ai/chat` — 對話式查詢（SSE 串流回應）
  - 接收使用者訊息
  - 呼叫 Claude API（Function Calling）
  - 定義 Function Tools：
    - `query_health_data` — 查詢健康數據
    - `query_care_logs` — 查詢照護日誌
    - `query_medications` — 查詢用藥紀錄
    - `query_expenses` — 查詢消費紀錄
    - `query_events` — 查詢行事曆
  - SSE 串流回應（`text/event-stream`）
  - 對話歷史存入 `ai_conversations` 表
- [ ] `POST /ai/care-analysis` — 照護記錄分析
  - 取得指定天數內的照護摘要
  - 呼叫 Claude API 產生分析報告
- [ ] `POST /ai/handover-report` — 看護交接報告
  - 彙整照護日誌 + 用藥紀錄 + 健康數據
  - Claude API 生成雙語報告
  - 選用：生成 PDF 存入 S3
- [ ] `POST /ai/subsidy-form` — 政府補助表單
  - Claude API 根據長者資料填寫表單
  - 標記缺漏欄位
  - 生成 PDF 存入 S3
- [ ] **個資保護 Middleware**：過濾 AI 回應中的敏感資訊（Email、電話、密碼等）

### 6.2 AI 急救小幫手 — RAG（功能 15.1–15.4）

- [ ] `POST /ai/first-aid` — 急救指引查詢
  - 使用者查詢 → Embedding → pgvector 相似度搜尋
  - 檢索相關急救文件段落
  - Claude API 基於檢索結果生成母語急救指引
  - 附帶資料來源 + 免責聲明
- [ ] RAG 資料準備：
  - [ ] 蒐集衛福部急救手冊、用藥指南 PDF
  - [ ] 文件分段（chunking）
  - [ ] 使用 Embedding Model（Voyage API）轉為向量
  - [ ] 寫入 pgvector
- [ ] RAG 管理腳本：批次更新文件向量

---

## Phase 7：推播通知系統

### 7.1 APNs 整合

- [ ] `POST /notifications/device` — 註冊裝置 Token
- [ ] `GET /notifications` — 通知列表（分頁、已讀篩選）
- [ ] `PUT /notifications/:id/read` — 標記已讀
- [ ] `PUT /notifications/read-all` — 全部已讀
- [ ] APNs Provider API 封裝：
  - HTTP/2 連線管理
  - JWT Token 簽名（APNs Auth Key）
  - 推播 Payload 建構（含翻譯標題/內容）
  - 送達失敗重試機制
- [ ] 推播觸發點整合（所有需要推播的業務邏輯）：

| 觸發時機 | 通知類型 | 接收者 |
|---|---|---|
| 健康數據異常 | `health_alert` | 全部家庭成員 |
| 到達服藥時間 | `medication_reminder` | 看護 + Watch |
| 看護確認餵藥 | `medication_confirmed` | 家屬 |
| 看護申請請假 | `leave_request` | 家屬 |
| 家屬核准/駁回請假 | `leave_approved/rejected` | 看護 |
| 看護發送採購需求 | `board_request` | 家屬 |
| 家屬確認採購需求 | `board_approved` | 看護 |
| 收據 OCR 完成 | `expense_scanned` | 看護 |
| SOS 觸發 | `sos_triggered` | 全部家庭成員 |
| 行程前提醒 | `event_reminder` | 對應成員 |
| 被指派代辦 | `todo_assigned` | 被指派者 |
| 收到聊天訊息 | `chat_message` | 接收者（離線時） |

---

## Phase 8：SOS 緊急呼叫

### 8.1 SOS API（功能 16.1–16.4）

- [ ] `POST /sos/trigger` — 觸發 SOS
  - 儲存 SOS 紀錄（位置、觸發者、時間）
  - **立即**推播通知所有家庭成員（高優先級 APNs）
  - 回應中包含通知狀態
- [ ] `GET /sos/history` — SOS 歷史紀錄

---

## Phase 9：檔案儲存服務

### 9.1 AWS S3 整合

- [ ] S3 Service 封裝（使用 Soto SDK）：
  - 上傳檔案（聊天圖片、餵藥照片、收據照片、文件）
  - 生成 Presigned URL（上傳/下載）
  - 刪除檔案
- [ ] S3 Bucket 結構規劃：

```
carebridge-storage/
├── avatars/{user_id}.jpg
├── chat/{message_id}.jpg
├── care-logs/{log_id}.jpg
├── medications/{confirm_id}.jpg
├── receipts/{scan_id}.jpg
├── documents/{doc_id}.pdf
├── reports/{report_id}.pdf
└── forms/{form_id}.pdf
```

- [ ] 圖片壓縮處理（上傳前或上傳後）
- [ ] 檔案大小限制驗證

---

## Phase 10：部署與 DevOps

### 10.1 部署準備

- [ ] Production Dockerfile 最佳化（multi-stage build）
- [ ] Nginx 設定（反向代理 + SSL + WebSocket Upgrade）
- [ ] AWS EC2 / GCP Cloud Run 部署
- [ ] PostgreSQL 正式環境設定（備份、連線池）
- [ ] Redis 正式環境設定
- [ ] SSL 憑證（Let's Encrypt）
- [ ] 環境變數管理（production `.env`）

### 10.2 CI/CD

- [ ] GitHub Actions workflow：
  - 自動跑測試
  - Docker build + push
  - 自動部署到 staging
- [ ] 健康檢查端點（`GET /health`）

### 10.3 監控與日誌

- [ ] 結構化日誌（JSON format）
- [ ] 錯誤追蹤
- [ ] API 回應時間監控

---

## Phase 11：測試

- [ ] 單元測試：所有 Service 層的業務邏輯
- [ ] 整合測試：API 端點測試（使用 Vapor XCTVapor）
- [ ] WebSocket 測試
- [ ] 負載測試：健康數據同步 API（高頻寫入場景）

---

## 跨模組自動連動（後端需特別處理）

以下功能涉及跨模組資料寫入，需在後端統一實作：

| 觸發動作 | 自動建立 | 實作位置 |
|---|---|---|
| 餵藥拍照確認（7.4） | 照護日誌 - 用藥紀錄（6.3） | `MedicationController.confirm()` |
| 完成代辦（12.3） | 照護日誌 - 活動紀錄（6.6） | `TodoController.update()` |
| 請假核准（9.2） | 行事曆事件（11） | `LeaveController.update()` |
| 新增藥物 + 開啟提醒（7.2） | 行事曆用藥事件（11.3） | `MedicationController.create()` |
| 健康數據異常（10.1） | 健康警示紀錄（10.7）+ 推播 | `HealthController.sync()` |

---

## 前後端協作約定

| 項目 | 規範 |
|---|---|
| Base URL | `https://api.carebridge.app/v1`（Production）/ `http://localhost:8080/v1`（Dev） |
| 認證 | `Authorization: Bearer {access_token}` |
| Content-Type | `application/json`（預設）/ `multipart/form-data`（檔案上傳） |
| 日期格式 | ISO 8601（`2026-04-08T14:30:00Z`） |
| 分頁 | `?page=1&limit=20`（預設 20 筆） |
| 錯誤格式 | `{ success: false, error: { code, message, details } }` |
| WebSocket | `wss://api.carebridge.app/v1/ws/chat/{id}?token={token}` |
| SSE | `Content-Type: text/event-stream`（AI 串流） |
