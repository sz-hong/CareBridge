# CareBridge 照護橋

**CareBridge** 是一款專為外籍看護、長者及其家屬設計的智慧照護管理 APP，旨在透過科技打破語言與距離的障礙，讓照護溝通更順暢、健康管理更即時、日常事務更透明。

本專案為參加 **2026 MAIC 行動應用創意競賽** 之作品。

## 核心特色

- **即時翻譯聊天** — 看護與家屬跨語言無障礙溝通（中/印尼/越南/菲律賓語）
- **健康監測儀表板** — 整合 Apple Watch / HealthKit，即時追蹤長者心率、血氧、步數等生理數據
- **照護日誌** — 每日照護紀錄，含用餐、用藥、活動、生命徵象等項目
- **用藥管理** — 藥物排程與提醒，餵藥拍照確認，避免漏服
- **消費記帳** — 收據 OCR 掃描，照護相關支出透明記錄
- **AI 智慧助理** — 照護建議、健康分析、交接報告生成（OpenAI GPT-4o）
- **SOS 緊急呼叫** — 一鍵求助，自動發送定位與通知所有家庭成員
- **Apple Watch 支援** — 長者端獨立運作，健康監測、跌倒偵測與 SOS

## 技術棧

| 類別 | 技術 |
|---|---|
| **前端** | Swift / SwiftUI / iOS 26 Liquid Glass |
| **後端** | Python 3.12 / Django 5.x / Django REST Framework |
| **資料庫** | PostgreSQL 16 + pgvector / Redis 7 |
| **AI** | OpenAI GPT-4o（Function Calling / SSE / Vision / Embedding） |
| **即時通訊** | Django Channels（WebSocket） |
| **背景任務** | Celery + Redis |
| **儲存** | AWS S3（django-storages） |
| **推播** | APNs（Apple Push Notification service） |
| **容器化** | Docker / Docker Compose |
| **平台** | iOS 26 / iPadOS 26 / watchOS 26 |

## 使用者角色

| 角色 | 說明 |
|---|---|
| 看護 | 外籍看護，負責日常照護紀錄與溝通 |
| 家屬 | 長者家屬，遠端關心與管理 |
| 長者 | 被照護者，主要透過 Apple Watch 互動 |

## 資料夾結構

```
CareBridge/
├── README.md
├── .gitignore
│
├── CareBridge_Feature_List.md          # 系統功能清單（96 項功能）
├── CareBridge_Tech_Stack.md            # 技術棧分析
├── CareBridge_Frontend_Tasks.md        # 前端開發工作清單
├── CareBridge_Backend_Tasks.md         # 後端開發工作清單
├── CareBridge_Database_Schema.md       # 資料庫 Schema 設計（22 張表）
│
├── CareBridge/                         # iOS App（SwiftUI 前端）
│   ├── App/
│   │   ├── CareBridgeApp.swift         # App 進入點
│   │   └── ContentView.swift           # 主畫面（TabView）
│   ├── Models/
│   │   └── AppModels.swift             # 資料模型定義
│   ├── Services/
│   │   ├── DataService.swift           # 資料服務 Protocol
│   │   ├── APIDataService.swift        # API 實作
│   │   └── MockDataService.swift       # Mock 資料（開發用）
│   ├── Views/
│   │   ├── Home/HomeView.swift         # 首頁（健康摘要、SOS）
│   │   ├── Chat/ChatListView.swift     # 聊天列表
│   │   ├── CareLog/CareLogView.swift   # 照護日誌
│   │   ├── Spending/SpendingView.swift # 消費記帳
│   │   ├── More/MoreView.swift         # 更多功能入口
│   │   ├── Health/HealthMonitorView.swift
│   │   ├── Medication/MedicationView.swift
│   │   ├── Calendar/SharedCalendarView.swift
│   │   ├── Calendar/TodoView.swift
│   │   ├── Leave/LeaveManagementView.swift
│   │   ├── Board/MessageBoardView.swift
│   │   ├── Document/DocumentsView.swift
│   │   ├── Notification/NotificationCenterView.swift
│   │   ├── AI/AIAgentView.swift        # AI 智慧助理
│   │   ├── AI/FirstAidView.swift       # AI 急救小幫手
│   │   ├── SOS/SOSView.swift           # SOS 緊急呼叫
│   │   ├── Auth/LoginView.swift
│   │   ├── Auth/JoinFamilyView.swift
│   │   └── Shared/ProfileView.swift
│   └── Resources/
│       └── Assets.xcassets/            # 圖片與顏色資源
│
├── backend/                            # Django 後端 API
│   ├── manage.py
│   ├── requirements.txt                # Python 依賴
│   ├── .env.example                    # 環境變數範本
│   │
│   ├── carebridge_api/                 # Django 專案設定
│   │   ├── settings/
│   │   │   ├── base.py                 # 共用設定
│   │   │   ├── development.py          # 開發環境（SQLite）
│   │   │   └── production.py           # 正式環境（PostgreSQL）
│   │   ├── urls.py                     # API v1 路由總入口
│   │   ├── celery.py                   # Celery 設定
│   │   ├── asgi.py                     # ASGI（WebSocket）
│   │   └── wsgi.py                     # WSGI
│   │
│   ├── apps/                           # Django Apps（15 個模組）
│   │   ├── auth_account/               # 認證與帳號管理
│   │   ├── family/                     # 家庭群組
│   │   ├── chat/                       # 即時聊天（WebSocket）
│   │   ├── board/                      # 留言板（採購需求）
│   │   ├── care_log/                   # 照護日誌
│   │   ├── medication/                 # 用藥管理
│   │   ├── expense/                    # 消費記帳（OCR）
│   │   ├── leave/                      # 請假管理
│   │   ├── health/                     # 健康監測（Watch 數據）
│   │   ├── calendar_event/             # 行事曆
│   │   ├── todo/                       # 代辦事項
│   │   ├── document/                   # 文件管理
│   │   ├── ai_assistant/               # AI 智慧助理 + RAG 急救
│   │   ├── sos/                        # SOS 緊急呼叫
│   │   └── notification/               # 通知 + 裝置管理
│   │
│   ├── core/                           # 共用模組
│   │   ├── pagination.py               # 統一分頁
│   │   ├── exceptions.py               # 統一錯誤回應
│   │   ├── permissions.py              # 角色權限
│   │   ├── translation.py              # OpenAI 翻譯服務
│   │   ├── apns.py                     # APNs 推播
│   │   └── storage.py                  # S3 儲存
│   │
│   ├── docker/
│   │   ├── Dockerfile
│   │   └── docker-compose.yml          # Django + PostgreSQL + Redis + Celery
│   │
│   └── docs/
│       └── first-aid-docs/             # RAG 用急救文件
│
├── CareBridge.xcodeproj/               # Xcode 專案設定
├── CareBridgeTests/                    # 單元測試
└── CareBridgeUITests/                  # UI 測試
```

## 後端開發環境設定

```bash
# 進入後端目錄
cd backend

# 建立虛擬環境
python -m venv venv
source venv/bin/activate        # macOS/Linux
source venv/Scripts/activate    # Windows (Git Bash)

# 安裝依賴
pip install -r requirements.txt

# 複製環境變數
cp .env.example .env

# 資料庫遷移
python manage.py migrate

# 啟動開發伺服器
python manage.py runserver
```

## 前端開發環境

- **Xcode 26+**
- **macOS Tahoe 26+**
- **iOS 26 Simulator 或實機**

## API 端點

後端提供 RESTful API，基礎路徑為 `/api/v1/`：

| 路徑 | 模組 |
|---|---|
| `/api/v1/auth/` | 認證（註冊/登入/JWT） |
| `/api/v1/families/` | 家庭管理 |
| `/api/v1/chats/` | 聊天 |
| `/api/v1/board/` | 留言板 |
| `/api/v1/care-logs/` | 照護日誌 |
| `/api/v1/medications/` | 用藥管理 |
| `/api/v1/expenses/` | 消費記帳 |
| `/api/v1/leaves/` | 請假管理 |
| `/api/v1/health-data/` | 健康監測 |
| `/api/v1/events/` | 行事曆 |
| `/api/v1/todos/` | 代辦事項 |
| `/api/v1/documents/` | 文件管理 |
| `/api/v1/ai/` | AI 智慧助理 |
| `/api/v1/sos/` | SOS 緊急呼叫 |
| `/api/v1/notifications/` | 通知系統 |
| `/api/v1/health/` | Health Check |

## 開發者後台

### 🗄️ MinIO 物件儲存後台

本地開發使用 MinIO 模擬 AWS S3，可在後台查看所有上傳的收據圖片與檔案。

| 項目 | 說明 |
|---|---|
| **Console** | http://localhost:9001 |
| **帳號** | `minioadmin` |
| **密碼** | `minioadmin` |

> 上傳的收據圖片（receipt）可在 MinIO Console 的 Bucket 中查看。

### 🔧 Django 後台

Django Admin 後台可管理所有資料庫資料（使用者、家庭、藥物、日誌等）。

| 項目 | 說明 |
|---|---|
| **Console** | http://127.0.0.1:8000/admin/ |

**建立後台登入帳號：**

```bash
docker compose -f docker/docker-compose.yml exec web python manage.py createsuperuser
```

## 團隊

唐寶與他的夥伴

## 授權

本專案為競賽作品，未經授權請勿轉載或使用。
