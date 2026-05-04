# CareBridge 照護橋

CareBridge 是一款面向外籍看護、長者與家屬的智慧照護管理 App。專案以 iOS App 搭配 Django API 後端，整合跨語言溝通、照護紀錄、健康監測、用藥提醒、消費記帳、AI 助理與 SOS 緊急支援。

本專案為 2026 MAIC 行動應用創意競賽作品。

## 功能亮點

- **跨語言照護溝通**：家庭聊天室、看護留言板、請假申請與多語翻譯情境。
- **照護日常管理**：照護日誌、用藥排程、餵藥確認、行事曆、代辦事項。
- **健康資料追蹤**：支援 HealthKit / Apple Watch 情境，呈現心率、血氧、步數與異常警示。
- **家庭協作**：家庭群組、成員管理、文件管理、推播通知與照護資訊共享。
- **消費透明化**：收據圖片上傳、照護支出紀錄、月結統計與分類摘要。
- **AI 照護助理**：以自然語言查詢照護資訊、產生照護分析、交接報告與急救指引。
- **緊急支援**：SOS 觸發、定位資訊、家庭成員通知與急救小幫手入口。

## 使用者角色

| 角色 | 主要用途 |
|---|---|
| 看護 | 記錄照護日常、回報用藥、提出採購或請假、與家屬溝通 |
| 家屬 | 建立家庭、管理成員、查看健康與照護資料、審核請假或採購需求 |
| 長者 | 主要透過 Apple Watch 情境提供健康資料與 SOS 互動 |

## 技術架構

| 層級 | 技術 |
|---|---|
| iOS App | Swift、SwiftUI、SwiftData、Keychain、UserNotifications |
| Apple 生態整合 | HealthKit、Swift Charts、CoreLocation、APNs |
| 後端 API | Python、Django、Django REST Framework、Simple JWT |
| 即時與背景任務 | Django Channels、Redis、Celery |
| 資料與儲存 | SQLite（開發）、PostgreSQL + pgvector（部署）、S3 / MinIO |
| AI | OpenAI API、Embedding、SSE 串流回應 |
| 開發與部署 | Docker、Docker Compose、Gunicorn、Uvicorn |

## 專案結構

```text
CareBridge/
├── CareBridge/                     # iOS App 原始碼
│   ├── App/                        # App 進入點與主 TabView
│   ├── Models/                     # Swift 資料模型與狀態模型
│   ├── Services/                   # API client、資料服務、Keychain、AppConfig
│   ├── Views/                      # SwiftUI 功能畫面
│   └── Resources/                  # App icon、String Catalog、多語系資源
├── CareBridge.xcodeproj/           # Xcode 專案
├── CareBridgeTests/                # iOS 單元測試
├── CareBridgeUITests/              # iOS UI 測試
├── backend/                        # Django API 後端
│   ├── apps/                       # 功能模組
│   ├── carebridge_api/             # Django 設定、URL、ASGI/WSGI、Celery
│   ├── core/                       # 共用權限、分頁、錯誤處理、通知與儲存
│   ├── docker/                     # Dockerfile 與 docker-compose.yml
│   ├── docs/                       # 後端資料文件
│   ├── manage.py
│   └── requirements.txt
├── Doc/                            # 補充技術文件、圖表與範例
├── CareBridge_API_Documentation.md
├── CareBridge_Database_Schema.md
├── CareBridge_Feature_List.md
├── CareBridge_Tech_Stack.md
└── README.md
```

## 開發需求

### iOS App

- macOS 與 Xcode 26 或更新版本
- iOS 26.4 Simulator 或實機
- Apple Developer 帳號（需要測試 APNs、HealthKit 或實機能力時）

### 後端

- Python 3.12+
- Docker Desktop（建議）
- PostgreSQL / Redis / MinIO（使用 Docker Compose 時會自動啟動）

## 快速開始

### 1. 啟動後端

建議先用 Docker Compose 啟動完整後端環境：

```powershell
cd C:\CareBridge\backend
Copy-Item .env.example .env
docker compose -f docker\docker-compose.yml up --build
```

另開一個 PowerShell 視窗執行資料庫遷移：

```powershell
cd C:\CareBridge\backend
docker compose -f docker\docker-compose.yml exec web python manage.py migrate
```

確認 API 可用：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health/
```

成功時會回傳：

```json
{"status":"ok"}
```

### 2. 建立管理員帳號

```powershell
cd C:\CareBridge\backend
docker compose -f docker\docker-compose.yml exec web python manage.py createsuperuser
```

建立完成後可開啟：

- Django Admin: `http://127.0.0.1:8000/admin/`
- MinIO Console: `http://127.0.0.1:9001/`

MinIO 預設帳密來自 `.env.example`：

```text
minioadmin / minioadmin
```

### 3. 啟動 iOS App

1. 用 Xcode 開啟 `CareBridge.xcodeproj`。
2. 確認 `CareBridge/Services/AppConfig.swift` 的 `mode` 符合你的後端位置。
3. 選擇 iOS Simulator 或實機。
4. Build & Run。

`AppConfig` 支援三種後端連線模式：

| 模式 | 用途 |
|---|---|
| `.simulator` | iOS Simulator 連到本機 `127.0.0.1:8000` |
| `.device` | 實機透過同 Wi-Fi LAN IP 連到開發機 |
| `.publicTunnel` | 實機透過公開 HTTPS host 測試 |

## 不使用 Docker 的後端啟動方式

開發環境預設使用 SQLite，因此只要 Python 環境即可跑基本 API：

```powershell
cd C:\CareBridge\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python manage.py migrate
python manage.py runserver
```

若要測試 Redis、Celery、WebSocket、MinIO 或 PostgreSQL，仍建議使用 Docker Compose。

## 後端 API

後端 API 基礎路徑為：

```text
/api/v1/
```

主要端點：

| 路徑 | 模組 |
|---|---|
| `/api/v1/health/` | Health check |
| `/api/v1/auth/` | 註冊、登入、登出、個人資料、加入家庭 |
| `/api/v1/auth/token/` | JWT token |
| `/api/v1/auth/token/refresh/` | JWT refresh |
| `/api/v1/families/` | 家庭與成員管理 |
| `/api/v1/chats/` | 聊天室與訊息 |
| `/api/v1/board/` | 採購需求與留言板 |
| `/api/v1/care-logs/` | 照護日誌 |
| `/api/v1/medications/` | 用藥管理 |
| `/api/v1/expenses/` | 消費記帳 |
| `/api/v1/leaves/` | 請假管理 |
| `/api/v1/health-data/` | 健康資料 |
| `/api/v1/events/` | 行事曆 |
| `/api/v1/todos/` | 代辦事項 |
| `/api/v1/documents/` | 文件管理 |
| `/api/v1/ai/` | AI 助理、照護分析、交接報告、急救指引 |
| `/api/v1/sos/` | SOS 紀錄與觸發 |
| `/api/v1/notifications/` | 通知與裝置 token |

更完整的 request / response 格式請參考 `CareBridge_API_Documentation.md`。

## 環境變數

後端環境變數範本位於：

```text
backend/.env.example
```

本機開發通常至少需要確認：

```env
DJANGO_ENV=development
DJANGO_DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1
OPENAI_API_KEY=sk-xxxxxxxxxxxxxxxx
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_STORAGE_BUCKET_NAME=carebridge-storage
AWS_S3_ENDPOINT_URL=http://localhost:9000
```

APNs、正式 S3、Email 與 PostgreSQL 連線資訊只在對應功能或部署情境下需要填寫。

## 測試

### 後端測試

```powershell
cd C:\CareBridge\backend
python manage.py test
```

### iOS 測試

在 Xcode 中選擇 `CareBridge` scheme 後執行 Test，或使用 `xcodebuild`：

```bash
xcodebuild test -project CareBridge.xcodeproj -scheme CareBridge -destination 'platform=iOS Simulator,name=iPhone 16'
```

## 相關文件

- `CareBridge_API_Documentation.md`：API 規格與整合說明。
- `CareBridge_Database_Schema.md`：資料表與資料模型設計。
- `CareBridge_Feature_List.md`：功能模組與角色矩陣。
- `CareBridge_Tech_Stack.md`：技術選型與架構說明。
- `Doc/diagrams/`：系統架構、SOS 流程、聊天翻譯流程與健康 AI 流程圖。

## 注意事項

- 本專案是競賽與原型開發用途，醫療、急救與健康分析內容不能取代專業醫療判斷。
- 請勿將真實金鑰、APNs 憑證、S3 憑證或個人健康資料提交到版本控制。
- 若公開 Django Admin 或物件儲存服務，務必加上存取限制與 HTTPS 保護。

## 授權

本專案為競賽作品，未經授權請勿轉載、散布或商業使用。
