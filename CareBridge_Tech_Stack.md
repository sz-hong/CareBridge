# CareBridge 照護橋 — 技術棧分析

> **版本**: v1.0
> **最後更新**: 2026/04/10
> **對應功能清單**: CareBridge_Feature_List v1.1（96 項功能）

---

## 目標硬體平台

| 裝置 | 系統版本 | 用途 |
|---|---|---|
| iPhone | iOS 26 | 看護與家屬的主要操作裝置（開發主力） |
| iPad | iPadOS 26 | 家屬端大螢幕檢視照護報告、健康圖表 |
| Apple Watch | watchOS 26 | 長者端穿戴裝置，健康監測與 SOS |

> **設計策略**: 以 iOS 26 為開發主力，採用 Liquid Glass 液態玻璃設計語言。SwiftUI 共用程式碼自動適配 iPadOS，watchOS 為獨立 Target。

---

## 1. 前端（Client Side）

### 1.1 程式語言與 UI 框架

| 技術 | 說明 | 對應功能 |
|---|---|---|
| **Swift** | Apple 原生開發語言，所有前端程式碼統一使用 | 全部 |
| **SwiftUI** | 宣告式 UI 框架，一套程式碼適配 iPhone / iPad / Watch，原生支援 Liquid Glass | 全部 UI |
| **Swift Charts** | Apple 原生圖表框架 | 健康趨勢折線圖（10.4）、消費圓餅圖與長條圖（8.5） |
| **WidgetKit** | 錶面小工具框架 | Apple Watch Complication（18.5） |

### 1.2 Apple 原生框架

| 框架 | 用途 | 對應功能 |
|---|---|---|
| **HealthKit** | 讀取 Apple Watch 健康數據（心率、血氧、步數、活動量） | 10.1, 10.2, 10.3, 10.4, 10.8 |
| **CoreMotion** (CMFallDetectionManager) | Apple Watch 跌倒偵測 | 18.6 |
| **WatchConnectivity** | iPhone ↔ Apple Watch 雙向資料同步 | 18.1–18.6 |
| **Speech** (SFSpeechRecognizer) | 語音轉文字（支援中/印尼/越南/菲律賓語） | 3.3, 4.5, 5.1, 6.7, 9.1, 15.1 |
| **AVFoundation** | 錄音、相機拍攝 | 4.5（語音錄製）, 7.4（餵藥拍照）, 8.1（收據拍照）, 6.5（飲食照片） |
| **PhotosUI** (PhotosPicker) | 從相簿選擇照片 | 4.4, 8.1 |
| **UserNotifications** | 本地通知排程（用藥提醒、行程提醒） | 7.3, 11.4 |
| **APNs** (UIApplication 註冊) | 遠端推播通知 | 17.1, 17.2 |
| **CoreLocation** | GPS 定位（SOS 發送位置） | 16.3, 16.4 |
| **CallKit / Tel URL Scheme** | 觸發撥打 119 緊急電話 | 16.2 |
| **QuickLook** | App 內文件預覽（PDF/圖片） | 13.3 |
| **PDFKit** | 產生 PDF 報告（照護日誌匯出、月結帳單、補助表單） | 14.4, 19.1, 19.3 |
| **UIKit** (UIActivityViewController) | 系統分享功能，匯出 PDF/CSV | 19.1, 19.2, 19.3 |
| **WKExtendedRuntimeSession** | Watch 背景執行延長（維持健康數據監測） | 18.1, 18.4 |
| **ClockKit / WidgetKit** | Watch 錶面小工具 | 18.5 |

### 1.3 架構模式

| 項目 | 選擇 | 說明 |
|---|---|---|
| 架構模式 | **MVVM** | SwiftUI 原生適配，View ↔ ViewModel 透過 `@Observable` 綁定 |
| 狀態管理 | **SwiftUI @Observable + @Environment** | iOS 17+ 新 Observation 框架，取代 ObservableObject |
| 導航 | **NavigationStack + NavigationPath** | 程式化導航，支援 deep link |
| 依賴注入 | **Environment + Swift Package** | 輕量 DI，無需第三方框架 |

### 1.4 本地儲存

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **SwiftData** | 結構化本地資料持久化（照護日誌草稿、離線快取） | 離線模式下的各模組資料快取 |
| **Keychain Services** | 安全儲存 JWT Token、Refresh Token | 1.2, 1.3, 1.5 |
| **UserDefaults** | 使用者偏好設定（語言、通知偏好、主題） | 1.4, 3.1, 17.5 |
| **FileManager** | 暫存下載文件與匯出檔案 | 13.3, 19.1–19.3 |

### 1.5 多語系

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **String Catalog (.xcstrings)** | Xcode 原生多語系管理，支援中/英/印尼/越南/菲律賓 | 3.1 |
| **Bundle.preferredLocalizations** | 動態切換 App 語言，無需重啟 | 3.1 |

---

## 2. 後端（Server Side）

### 2.1 程式語言與框架

| 技術 | 說明 | 理由 |
|---|---|---|
| **Swift** | 後端語言 | 前後端統一語言，Apple 生態系原生支持 |
| **Vapor** | Swift Server-Side 框架 | Apple 生態系首選後端框架，支援 async/await、Codable 直接共用 Model |
| **Fluent ORM** | Vapor 內建 ORM | 資料庫操作，支援 PostgreSQL，與 Vapor 無縫整合 |

> **備選方案**: 若團隊對 Vapor 不熟悉，可考慮 **Node.js (Express/Fastify)** 或 **Python (FastAPI)** 作為替代，但建議優先使用 Swift 以展現 Apple 生態系整合度。

### 2.2 API 設計

| 項目 | 選擇 | 對應功能 |
|---|---|---|
| API 風格 | **RESTful JSON** | 全部模組的 CRUD 操作 |
| 認證機制 | **JWT (Access Token + Refresh Token)** | 1.2, 1.3 |
| 即時通訊 | **WebSocket** | 聊天訊息即時推送（4.1–4.7）、「正在輸入」狀態（4.6） |
| AI 串流回應 | **Server-Sent Events (SSE)** | AI 智慧助理串流回覆（14.1, 14.5） |
| 檔案上傳 | **multipart/form-data** | 圖片（4.4, 7.4, 8.1）、文件上傳（13.1） |

### 2.3 資料庫

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **PostgreSQL** | 主要關聯式資料庫，儲存使用者、家庭、照護紀錄、用藥、行事曆等結構化資料 | 全部模組 |
| **Redis** | 快取層 + WebSocket 狀態管理 + Token 黑名單 | 1.3（Token 刷新）, 4.6（輸入狀態）, 4.7（未讀計數） |
| **向量資料庫 (pgvector)** | 儲存急救手冊嵌入向量，供 RAG 檢索 | 15.3 |

> 使用 PostgreSQL + pgvector 擴展，無需額外部署獨立向量資料庫。

### 2.4 檔案儲存

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **AWS S3 / 相容物件儲存** | 儲存圖片（聊天照片、餵藥照片、收據照片）、文件（PDF/證件）| 4.4, 6.5, 7.4, 8.1, 13.1 |
| **預簽名 URL (Presigned URL)** | 產生有時效的下載/上傳連結 | 13.3 |

### 2.5 部署與基礎設施

| 技術 | 用途 |
|---|---|
| **Docker** | 容器化部署 Vapor 應用 |
| **Docker Compose** | 本地開發環境編排（API + PostgreSQL + Redis） |
| **AWS EC2 / GCP Cloud Run** | 正式環境部署 |
| **Nginx** | 反向代理、SSL 終端、WebSocket 升級 |

---

## 3. AI 與機器學習

### 3.1 LLM 服務

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **Apple Intelligence / Foundation Models** | 裝置端 AI 推論（文字摘要、翻譯輔助），展現 Apple 生態整合 | 3.2, 14.2 |
| **Claude API (Anthropic)** | 雲端 LLM，用於 AI 智慧助理對話、Function Calling、照護報告生成、補助表單填寫 | 14.1–14.6 |
| **Claude API + Function Calling** | AI Agent 透過 Function Calling 查詢 App 資料庫，回覆使用者問題 | 14.1, 14.5 |
| **Claude API + SSE** | 串流回應，提升對話體驗 | 14.1 |

> **策略**: 優先使用 Apple Intelligence 處理裝置端任務（隱私優先），複雜推理與報告生成交由 Claude API。

### 3.2 翻譯服務

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **Apple Translation Framework** | iOS 26 原生翻譯 API，支援裝置端離線翻譯，零額外成本 | 3.2, 3.3, 4.3, 5.1, 7.6, 9.1 |

> Translation Framework 支援中文 ↔ 印尼語/越南語/菲律賓語（Tagalog），可離線運作，是 MAIC 競賽的加分項。若特定語言對不支援，fallback 到 Claude API 翻譯。

### 3.3 語音辨識

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **Speech Framework** (SFSpeechRecognizer) | Apple 原生語音轉文字，支援多語言辨識 | 3.3, 4.5, 5.1, 6.7, 9.1, 15.1 |

> 支援中文、印尼語、越南語。菲律賓語（Tagalog）部分支援，可搭配 Translation Framework 補強。

### 3.4 OCR 文字辨識

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **Vision Framework** (VNRecognizeTextRequest) | Apple 原生 OCR，辨識收據上的文字 | 8.2 |
| **Claude API** | OCR 結果的結構化解析（品名、金額、分類），LLM 理解非結構化收據格式 | 8.2 |

> 流程：Vision OCR 擷取原始文字 → Claude API 結構化解析為 JSON（品名、數量、金額、日期、分類）。

### 3.5 RAG（檢索增強生成）

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **pgvector** | 儲存衛福部急救手冊 / 用藥指南的文字嵌入向量 | 15.3 |
| **Embedding Model** | 將查詢與文件轉為向量（可使用 Voyage API 或開源模型） | 15.3 |
| **Claude API** | 基於檢索結果生成母語急救指引 | 15.3 |

---

## 4. 推播通知

| 技術 | 用途 | 對應功能 |
|---|---|---|
| **APNs (Apple Push Notification service)** | 所有遠端推播通知的唯一通道 | 17.1–17.5 |
| **APNs Provider API (HTTP/2)** | 後端透過 HTTP/2 向 APNs 發送推播 | 17.2 |
| **Background App Refresh** | 確保 App 在背景也能接收並處理通知 | 10.6, 16.3 |

> 不使用 Firebase Cloud Messaging (FCM)，直接使用 APNs 原生方案，符合 Apple 生態系優先原則。

---

## 5. 第三方套件（Swift Package Manager）

所有第三方依賴統一透過 **Swift Package Manager (SPM)** 管理，不使用 CocoaPods 或 Carthage。

| 套件 | 用途 | 對應功能 |
|---|---|---|
| **swift-jwt** (Vapor) | 後端 JWT Token 生成與驗證 | 1.2, 1.3 |
| **Kingfisher** | 圖片非同步載入與快取 | 4.4, 6.5, 7.4, 8.1 |
| **swift-markdown-ui** | Markdown 渲染（AI 回覆內容） | 14.1 |

> 原則：能用 Apple 原生框架就不引入第三方套件，減少依賴風險。

---

## 6. 開發工具與流程

| 工具 | 用途 |
|---|---|
| **Xcode 26** | 主要 IDE，支援 iOS 26 / watchOS 26 / iPadOS 26 |
| **Swift Package Manager** | 依賴管理 |
| **Git + GitHub** | 版本控制與協作 |
| **GitHub Actions** | CI/CD，自動建置與測試 |
| **TestFlight** | Beta 測試分發 |
| **Xcode Instruments** | 效能分析（記憶體、CPU、網路） |
| **Xcode Previews** | SwiftUI 即時預覽 |

---

## 7. 技術棧總覽圖

```
┌─────────────────────────────────────────────────────────────┐
│                     Client (Apple Devices)                   │
│                                                             │
│  iPhone / iPad                    Apple Watch               │
│  ┌───────────────────────┐        ┌──────────────────────┐  │
│  │ Swift + SwiftUI       │        │ Swift + SwiftUI      │  │
│  │ MVVM + @Observable    │        │ WatchKit             │  │
│  │ SwiftData (本地快取)   │◄──────►│ HealthKit            │  │
│  │ Swift Charts          │  Watch │ CoreMotion (跌倒)    │  │
│  │ HealthKit             │  Conn. │ WKExtendedRuntime    │  │
│  │ Speech Framework      │        │ ClockKit/WidgetKit   │  │
│  │ Vision (OCR)          │        └──────────────────────┘  │
│  │ Translation Framework │                                  │
│  │ PDFKit                │                                  │
│  │ CoreLocation          │                                  │
│  └──────────┬────────────┘                                  │
│             │                                               │
└─────────────┼───────────────────────────────────────────────┘
              │ REST API / WebSocket / SSE
              │ APNs (Push Notifications)
              ▼
┌─────────────────────────────────────────────────────────────┐
│                     Server (Backend)                         │
│                                                             │
│  ┌───────────────────────┐    ┌──────────────────────────┐  │
│  │ Swift + Vapor         │    │ PostgreSQL               │  │
│  │ Fluent ORM            │───►│ + pgvector (RAG 向量)    │  │
│  │ JWT 認證              │    └──────────────────────────┘  │
│  │ WebSocket (聊天)      │                                  │
│  │ SSE (AI 串流)         │    ┌──────────────────────────┐  │
│  │ APNs Provider API     │───►│ Redis (快取/狀態)        │  │
│  └──────────┬────────────┘    └──────────────────────────┘  │
│             │                                               │
│             │                 ┌──────────────────────────┐  │
│             │────────────────►│ AWS S3 (檔案儲存)        │  │
│             │                 └──────────────────────────┘  │
└─────────────┼───────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│                     AI Services                              │
│                                                             │
│  ┌─────────────────────┐  ┌───────────────────────────────┐ │
│  │ Claude API           │  │ Apple Intelligence            │ │
│  │ - Function Calling   │  │ - 裝置端摘要/分類            │ │
│  │ - SSE 串流回應       │  │ - 隱私優先處理              │ │
│  │ - OCR 結構化解析     │  └───────────────────────────────┘ │
│  │ - RAG 急救指引       │                                   │
│  │ - 報告/表單生成      │  ┌───────────────────────────────┐ │
│  └─────────────────────┘  │ Voyage Embedding API          │ │
│                            │ - 文件向量化 (RAG)            │ │
│                            └───────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. 功能 → 技術對照表

| 功能模組 | 前端技術 | 後端技術 | AI / 外部服務 |
|---|---|---|---|
| 認證與帳號 (1) | Keychain, SwiftUI | Vapor, JWT, Fluent | — |
| 家庭管理 (2) | SwiftUI | Vapor, Fluent | — |
| 即時翻譯 (3) | Translation Framework, Speech | — | Apple Translation（離線）, Claude API（fallback） |
| 即時聊天 (4) | SwiftUI, AVFoundation | WebSocket, Redis, S3 | — |
| 留言板 (5) | SwiftUI | Vapor, Fluent | — |
| 照護日誌 (6) | SwiftUI, AVFoundation, Speech | Vapor, Fluent, S3 | — |
| 用藥管理 (7) | SwiftUI, UserNotifications | Vapor, Fluent, APNs | Translation Framework |
| 消費記帳 (8) | SwiftUI, AVFoundation, Vision | Vapor, Fluent, S3 | Claude API（OCR 結構化） |
| 請假管理 (9) | SwiftUI, Speech | Vapor, Fluent, APNs | Translation Framework |
| 健康監測 (10) | HealthKit, Swift Charts | Vapor, Fluent | Apple Intelligence（趨勢分析） |
| 行事曆 (11) | SwiftUI | Vapor, Fluent | — |
| 代辦事項 (12) | SwiftUI | Vapor, Fluent, APNs | — |
| 文件管理 (13) | QuickLook, SwiftUI | Vapor, S3 (Presigned URL) | — |
| AI 智慧助理 (14) | SwiftUI, swift-markdown-ui | Vapor, SSE, Fluent | Claude API (Function Calling) |
| AI 急救小幫手 (15) | SwiftUI, Speech | Vapor, pgvector | Claude API + RAG, Voyage Embedding |
| SOS 緊急呼叫 (16) | CoreLocation, CallKit | Vapor, APNs | — |
| 通知系統 (17) | UserNotifications | APNs Provider API, Redis | — |
| Apple Watch (18) | HealthKit, CoreMotion, WatchConnectivity, WidgetKit | — | — |
| 資料匯出 (19) | PDFKit, UIActivityViewController | Vapor, Fluent | — |
