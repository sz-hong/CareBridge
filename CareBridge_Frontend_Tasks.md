# CareBridge 照護橋 — 前端開發工作清單

> **負責範圍**: iOS App (iPhone/iPad) + watchOS App (Apple Watch)
> **技術棧**: Swift + SwiftUI + Apple 原生框架
> **最後更新**: 2026/04/11

---

## 目前完成狀態

已完成第一版 UI 靜態畫面（16 個 SwiftUI View + 1 個 Model），使用寫死的 sample data。

---

## Phase 1：架構建立與基礎建設

### 1.1 專案架構重構

- [ ] 將現有程式碼重構為 **MVVM** 架構（View / ViewModel / Model / Service 分層）
- [ ] 建立統一的資料夾結構：

```
CareBridge/
├── App/                    # CareBridgeApp.swift, ContentView.swift
├── Models/                 # 所有資料模型（Codable struct）
├── ViewModels/             # 每個 View 對應的 ViewModel（@Observable）
├── Views/
│   ├── Auth/               # 登入、註冊、忘記密碼
│   ├── Home/               # 首頁
│   ├── Chat/               # 聊天
│   ├── CareLog/            # 照護日誌
│   ├── Spending/           # 消費記帳
│   ├── Health/             # 健康監測
│   ├── Medication/         # 用藥管理
│   ├── Calendar/           # 行事曆 + 代辦
│   ├── Board/              # 留言板
│   ├── Leave/              # 請假管理
│   ├── Document/           # 文件管理
│   ├── AI/                 # AI 助理 + 急救
│   ├── SOS/                # SOS 緊急呼叫
│   ├── Notification/       # 通知中心
│   ├── More/               # 更多功能
│   └── Shared/             # 共用元件
├── Services/
│   ├── APIClient.swift     # 網路層封裝
│   ├── AuthService.swift   # 認證邏輯
│   ├── WebSocketService.swift
│   ├── HealthKitService.swift
│   ├── TranslationService.swift
│   ├── NotificationService.swift
│   └── LocationService.swift
├── Utilities/              # 擴展、Helper
├── Resources/              # Assets, Localizable
└── CareBridge.xcstrings    # 多語系
```

- [ ] 建立 `@Observable` 為基礎的 ViewModel 基類
- [ ] 設定 NavigationStack + NavigationPath 統一導航

### 1.2 網路層（APIClient）

- [ ] 建立 `APIClient` 封裝 URLSession，統一處理：
  - Base URL 設定
  - JWT Token 自動附加（Bearer Header）
  - Token 過期自動刷新（401 → refresh → retry）
  - 統一錯誤回應解析（`APIError` enum）
  - 通用分頁參數處理
  - `multipart/form-data` 上傳封裝
- [ ] 建立所有 API 的 Request/Response Codable Model（對照 API Documentation）
- [ ] 建立 `SSEClient` 處理 AI 串流回應（`text/event-stream`）

### 1.3 本地儲存

- [ ] Keychain 封裝：安全儲存 JWT Access Token / Refresh Token
- [ ] UserDefaults 封裝：語言偏好、通知設定、主題
- [ ] SwiftData Model 定義：離線快取 schema（照護日誌草稿、聊天訊息快取）

### 1.4 多語系

- [ ] 建立 `.xcstrings` String Catalog，支援：中文（zh-TW）、印尼語（id）、越南語（vi）、菲律賓語（tl）
- [ ] 所有 View 中的硬編碼字串改為 `String(localized:)` 呼叫
- [ ] 實作 App 內語言切換（不依賴系統語言設定）

---

## Phase 2：認證與核心流程

### 2.1 認證模組（功能 1.1–1.8）

- [ ] 登入頁面 → 呼叫 `POST /auth/login` → 儲存 Token 至 Keychain
- [ ] 註冊頁面 → 角色選擇（看護/家屬/長者）→ 呼叫 `POST /auth/register`
- [ ] 忘記密碼頁面 → Email 輸入 → 呼叫重設 API
- [ ] Token 自動刷新邏輯（`POST /auth/refresh`）
- [ ] 個人檔案編輯頁 → 呼叫 `PUT /users/:id`
- [ ] 帳號刪除功能
- [ ] 隱私權政策 / 使用條款頁面（WebView 或靜態頁）
- [ ] 登出 → 清除 Keychain → 導航回登入頁

### 2.2 家庭管理（功能 2.1–2.4）

- [ ] 建立家庭群組頁面 → `POST /families`
- [ ] 加入家庭（輸入邀請碼）→ `POST /families/:id/members`
- [ ] 家庭成員列表 → `GET /families/:id`
- [ ] 成員管理（踢除成員、重新產生邀請碼）

---

## Phase 3：照護核心功能

### 3.1 即時聊天（功能 4.1–4.7）

- [ ] 聊天列表頁 → `GET /chats` → 顯示未讀計數
- [ ] 聊天室頁面 → WebSocket 連線（`wss://...`）
- [ ] 文字訊息收發 + 即時翻譯雙語顯示
- [ ] 圖片訊息：使用 PhotosPicker / AVFoundation 拍照 → 上傳
- [ ] 語音輸入：SFSpeechRecognizer → 轉文字後發送
- [ ] 「正在輸入」狀態顯示
- [ ] 圖片非同步載入（Kingfisher）

### 3.2 照護日誌（功能 6.1–6.7）

- [ ] 時間軸頁面 → `GET /care-logs` → 無限滾動分頁
- [ ] 類型篩選 tab（用藥/生理/飲食/活動/備註）
- [ ] 新增紀錄表單：
  - 用藥紀錄（藥名、劑量、拍照）
  - 生理數值（血壓、血糖、體溫 手動輸入）
  - 飲食紀錄（三餐、食慾、照片）
  - 活動紀錄（活動類型、時長）
  - 備註（文字 + 語音輸入）
- [ ] 上傳照片（multipart/form-data）

### 3.3 用藥管理（功能 7.1–7.6）

- [ ] 藥物清單頁 → `GET /medications`
- [ ] 新增/編輯藥物表單 → `POST/PUT /medications`
- [ ] 餵藥拍照確認流程 → `POST /medications/:id/confirm` → 自動觸發照護日誌
- [ ] 本地排程通知（UserNotifications）配合後端 APNs
- [ ] 藥物說明翻譯顯示

### 3.4 健康監測（功能 10.1–10.8）

- [ ] 首頁儀表板 → `GET /health/dashboard` → 心率/血氧即時數值 + 狀態指示
- [ ] 歷史數據圖表 → `GET /health/data` → Swift Charts 折線圖（日/週/月切換）
- [ ] 異常閾值設定頁面
- [ ] 異常紀錄列表 → `GET /health/alerts`
- [ ] HealthKit 讀取整合（從 Watch 同步的數據）
- [ ] HealthKit 授權請求與狀態管理

### 3.5 消費記帳（功能 8.1–8.5）

- [ ] 拍攝收據 → AVFoundation 相機 + 導引框 → `POST /expenses/scan`
- [ ] OCR 結果確認/修正頁面 → `PUT /expenses/:id`
- [ ] 消費紀錄列表 → `GET /expenses`（日期/分類篩選）
- [ ] 月結帳單 → `GET /expenses/monthly` → Swift Charts（甜甜圈圖 + 長條圖）

---

## Phase 4：輔助功能模組

### 4.1 行事曆（功能 11.1–11.5）

- [ ] 月視圖 / 日視圖 → `GET /events`
- [ ] 新增/編輯/刪除行程
- [ ] 用藥提醒自動顯示（`type: medication`）
- [ ] 行程提醒本地通知

### 4.2 代辦事項（功能 12.1–12.3）

- [ ] 代辦列表 → `GET /todos`
- [ ] 新增代辦（指派對象、優先度、到期日）
- [ ] 完成代辦 → `PUT /todos/:id`

### 4.3 留言板（功能 5.1–5.4）

- [ ] 採購需求列表 → `GET /boards/requests`（狀態篩選）
- [ ] 新增需求表單（語音輸入 + 自動翻譯）
- [ ] 確認/駁回操作 → `PUT /boards/requests/:id`

### 4.4 請假管理（功能 9.1–9.4）

- [ ] 請假申請表單 → `POST /leaves`
- [ ] 請假紀錄列表 → `GET /leaves`
- [ ] 審核操作（核准/駁回）→ `PUT /leaves/:id`

### 4.5 文件管理（功能 13.1–13.4）

- [ ] 文件列表 → `GET /documents`（分類篩選）
- [ ] 上傳文件 → `POST /documents`（multipart/form-data）
- [ ] 預覽文件 → QuickLook（Presigned URL）
- [ ] 刪除文件 → `DELETE /documents/:id`

### 4.6 通知中心（功能 17.1–17.5）

- [ ] APNs Device Token 註冊 → `POST /notifications/device`
- [ ] 通知列表 → `GET /notifications`（已讀/未讀篩選）
- [ ] 標記已讀 → `PUT /notifications/:id/read`
- [ ] 通知偏好設定頁面
- [ ] 通知點擊跳轉（deep link 至對應頁面）

---

## Phase 5：AI 功能

### 5.1 AI 智慧助理（功能 14.1–14.6）

- [ ] 對話式 UI → `POST /ai/chat` → SSE 串流接收 + 逐字顯示
- [ ] Markdown 渲染（swift-markdown-ui）
- [ ] 多輪對話（conversation_id 管理）
- [ ] 照護分析報告呈現 → `POST /ai/care-analysis`
- [ ] 交接報告生成 + 雙語顯示 → `POST /ai/handover-report`
- [ ] 政府補助表單 → `POST /ai/subsidy-form` → PDF 預覽/分享

### 5.2 AI 急救小幫手（功能 15.1–15.4）

- [ ] 緊急狀況輸入（文字 + 語音）→ `POST /ai/first-aid`
- [ ] 快速情境按鈕（暈倒/胸痛/跌倒/呼吸困難/嘔吐/出血）
- [ ] 母語急救指引顯示（含來源引用 + 免責聲明）
- [ ] SOS 快捷按鈕常駐

---

## Phase 6：SOS 與緊急功能

### 6.1 SOS 緊急呼叫（功能 16.1–16.4）

- [ ] SOS 按鈕 → 3 秒倒數動畫 → 確認觸發
- [ ] CoreLocation 取得 GPS 位置 → `POST /sos/trigger`
- [ ] 自動撥打 119（Tel URL Scheme / CallKit）
- [ ] SOS 歷史紀錄 → `GET /sos/history`

---

## Phase 7：翻譯整合

### 7.1 即時翻譯（功能 3.1–3.3）

- [ ] **Apple Translation Framework** 整合：
  - 聊天訊息翻譯
  - 留言板品項翻譯
  - 請假原因翻譯
  - 藥物說明翻譯
- [ ] 離線翻譯下載管理（Translation Framework 語言包）
- [ ] 語音轉文字 → SFSpeechRecognizer → 翻譯
- [ ] Fallback 機制：Translation Framework 不支援的語言對 → 呼叫後端 `POST /translate`

---

## Phase 8：資料匯出

### 8.1 匯出功能（功能 19.1–19.3）

- [ ] 照護日誌匯出 → PDFKit 生成 PDF（日期區間選擇）
- [ ] 健康數據匯出 → 生成 CSV 檔案
- [ ] 消費紀錄匯出 → PDFKit 生成月結帳單 PDF
- [ ] UIActivityViewController 系統分享

---

## Phase 9：Apple Watch App

### 9.1 watchOS Target 建立

- [ ] 建立 watchOS 26 App Target
- [ ] WatchConnectivity 雙向同步設定（iPhone ↔ Watch）

### 9.2 Watch 功能實作（功能 18.1–18.6）

- [ ] 即時生理數值頁面（心率 + 血氧）
- [ ] HealthKit 讀取 → 透過 WatchConnectivity 或直接呼叫 API 同步
- [ ] SOS 按鈕（3 秒倒數 → 觸發 → 震動回饋）
- [ ] 用藥提醒通知接收 + 確認按鈕
- [ ] 異常觸覺回饋（WKInterfaceDevice haptic）
- [ ] Complication（WidgetKit — 錶面心率小工具）
- [ ] 跌倒偵測（CMFallDetectionManager → 自動觸發 SOS）
- [ ] WKExtendedRuntimeSession（背景持續監測）

---

## Phase 10：UI 精修與 Liquid Glass

### 10.1 iOS 26 設計語言

- [ ] 全面導入 Liquid Glass 設計語言
- [ ] 調整 Navigation Bar、Tab Bar、Sheet 的 glassMorphism 效果
- [ ] 動態色彩與模糊效果適配
- [ ] iPad 大螢幕自適應佈局（NavigationSplitView）

### 10.2 共用元件庫

- [ ] 統一按鈕樣式（Primary / Secondary / Danger）
- [ ] 統一卡片元件（Card with shadow）
- [ ] 統一空狀態頁面
- [ ] 統一錯誤提示 / Toast 元件
- [ ] Loading 狀態元件

---

## 前後端協作介面

前端需要後端提供的內容：

| 項目 | 說明 |
|---|---|
| **API 文件** | 已完成（CareBridge_API_Documentation.md），需持續同步更新 |
| **WebSocket 事件格式** | 聊天即時訊息、typing 狀態的事件格式 |
| **SSE 事件格式** | AI 串流回應的事件格式 |
| **APNs Payload 格式** | 各類推播通知的 payload 結構 |
| **Presigned URL 機制** | 檔案上傳/下載的 presigned URL 產生方式 |
| **錯誤碼定義** | 完整的業務錯誤碼清單 |
