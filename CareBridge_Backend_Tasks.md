# CareBridge 照護橋 — 後端開發工作清單

> **負責範圍**: Server API + 資料庫 + AI 整合 + 推播 + 部署
> **技術棧**: Python (Django) + Django REST Framework + PostgreSQL + Redis + Celery
> **最後更新**: 2026/04/11

---

## Phase 1：專案初始化與基礎建設

### 1.1 Django 專案建立

- [ ] 使用 `django-admin startproject carebridge_api` 初始化專案
- [ ] 建立各 Django App 與專案結構：

```
carebridge_api/
├── manage.py
├── requirements.txt             # 或 pyproject.toml (Poetry)
├── .env                         # 環境變數（DB、Redis、JWT Secret、S3、OpenAI API Key）
├── carebridge_api/              # 專案設定
│   ├── settings/
│   │   ├── base.py              # 共用設定
│   │   ├── development.py       # 開發環境
│   │   └── production.py        # 正式環境
│   ├── urls.py                  # 路由總入口
│   ├── asgi.py                  # ASGI 設定（WebSocket）
│   └── celery.py                # Celery 設定
│
├── apps/
│   ├── auth_account/            # 認證與帳號（App 1）
│   │   ├── models.py            # User Model（擴展 AbstractUser）
│   │   ├── serializers.py       # DRF Serializer
│   │   ├── views.py             # ViewSet / APIView
│   │   ├── urls.py
│   │   └── permissions.py       # 角色權限
│   ├── family/                  # 家庭管理（App 2）
│   ├── chat/                    # 即時聊天（App 3）
│   │   ├── consumers.py         # WebSocket Consumer（Channels）
│   │   ├── routing.py           # WebSocket 路由
│   │   └── ...
│   ├── board/                   # 留言板（App 4）
│   ├── care_log/                # 照護日誌（App 5）
│   ├── medication/              # 用藥管理（App 6）
│   ├── expense/                 # 消費記帳（App 7）
│   ├── leave/                   # 請假管理（App 8）
│   ├── health/                  # 健康監測（App 9）
│   ├── calendar_event/          # 行事曆（App 10）
│   ├── todo/                    # 代辦事項（App 11）
│   ├── document/                # 文件管理（App 12）
│   ├── ai_assistant/            # AI 智慧助理 + 急救（App 13）
│   ├── sos/                     # SOS 緊急呼叫（App 14）
│   └── notification/            # 通知系統（App 15）
│
├── core/                        # 共用模組
│   ├── pagination.py            # 統一分頁設定
│   ├── exceptions.py            # 統一錯誤回應格式
│   ├── permissions.py           # 共用角色權限 class
│   ├── translation.py           # 翻譯服務封裝
│   ├── apns.py                  # APNs 推播封裝
│   └── storage.py               # S3 儲存封裝
│
├── docker/
│   ├── Dockerfile
│   └── docker-compose.yml       # Django + PostgreSQL + Redis + Celery Worker
│
└── docs/
    └── first-aid-docs/          # RAG 用急救文件
```

### 1.2 依賴安裝（requirements.txt）

```
django>=5.0
djangorestframework
djangorestframework-simplejwt
django-channels[daphne]
channels-redis
celery[redis]
django-storages[s3]
boto3
django-redis
django-cors-headers
django-filter
openai
pgvector
apns2
Pillow
gunicorn
uvicorn[standard]
psycopg[binary]
python-dotenv
```

### 1.3 Docker 本地開發環境

- [ ] 撰寫 `Dockerfile`（Python 3.12 + Django）
- [ ] 撰寫 `docker-compose.yml`：
  - Django API Server（port 8000）
  - PostgreSQL 16（port 5432）+ pgvector 擴展
  - Redis 7（port 6379）
  - Celery Worker（處理背景任務）
  - Celery Beat（定時任務排程）
- [ ] `.env` 環境變數管理

### 1.4 Django 基礎設定

- [ ] `settings/base.py`：
  - `INSTALLED_APPS` 加入所有 app + DRF + Channels + corsheaders
  - DRF 預設設定（分頁、認證、權限、例外處理）
  - JWT 設定（Access Token 1hr / Refresh Token 30 days）
  - Channels Layer 設定（Redis backend）
  - Celery 設定（Redis broker）
  - S3 Storage 設定
  - CORS 設定
- [ ] 統一回應格式：

```python
# 成功：{ "success": true, "data": {...}, "meta": {...} }
# 錯誤：{ "success": false, "error": { "code": "...", "message": "...", "details": [...] } }
```

- [ ] 自訂 Exception Handler 對應 API 文件的錯誤碼

### 1.5 資料庫 Model 與 Migration

- [ ] 自訂 User Model（擴展 `AbstractUser`）：
  - 欄位：email, name, role, language, phone, family_id, avatar_url
  - role choices: `caregiver`, `family_member`, `elder`
  - language choices: `zh-TW`, `id`, `vi`, `tl`
- [ ] 建立所有 Model（對應 API 文件附錄的 18 張資料表）
- [ ] 啟用 pgvector 擴展（Migration 中執行 `CREATE EXTENSION vector`）
- [ ] 建立必要的 Index：
  - `users.email`（唯一索引）
  - `health_data(family_id, type, recorded_at)`（複合索引）
  - `care_logs(family_id, timestamp)`
  - `messages(chat_id, sent_at)`
  - `notifications(user_id, read, created_at)`
- [ ] `python manage.py makemigrations && migrate`

### 1.6 Django Admin 設定

- [ ] 為所有 Model 註冊 Admin
- [ ] 自訂 Admin 顯示：User（角色/語言篩選）、CareLog（類型篩選）、HealthData（圖表）
- [ ] Admin 可作為開發期間的資料管理工具與 Demo 後台

### 1.7 共用權限系統

- [ ] 建立角色權限 Permission Class（對照 API 文件的角色權限矩陣）：

```python
class IsCaregiverOrFamilyMember(BasePermission): ...
class IsFamilyMemberOnly(BasePermission): ...
class IsCaregiverOnly(BasePermission): ...
class IsPrimaryFamilyMember(BasePermission): ...
class IsFamilyMember(BasePermission): ...  # 確認使用者屬於該家庭
```

---

## Phase 2：認證與使用者管理

### 2.1 認證 API（功能 1.1–1.8）

- [ ] `POST /auth/register` — 註冊
  - Django 密碼 hash（`make_password`）
  - SimpleJWT 產生 Token pair
  - Email 唯一性驗證（Serializer `validate_email`）
- [ ] `POST /auth/login` — 登入（SimpleJWT `TokenObtainPairView` 自訂）
- [ ] `POST /auth/refresh` — Token 刷新（SimpleJWT `TokenRefreshView`）
  - 舊 Refresh Token 加入 Redis 黑名單（`SIMPLE_JWT.ROTATE_REFRESH_TOKENS = True`）
- [ ] `GET /auth/me` — 取得個人資訊
- [ ] `POST /auth/forgot-password` — 寄送密碼重設信
  - 產生有時效的重設 Token（Django `PasswordResetTokenGenerator` 或 Redis 15 分鐘 TTL）
  - Email 發送（`django.core.mail` + SMTP / AWS SES）
- [ ] `POST /auth/reset-password` — 重設密碼
- [ ] `DELETE /auth/account` — 刪除帳號（級聯刪除 `on_delete=CASCADE`）
- [ ] `PUT /users/:id` — 更新個人資訊（含頭像上傳 S3）

### 2.2 家庭管理 API（功能 2.1–2.4）

- [ ] `POST /families` — 建立家庭群組
  - 自動產生 8 位邀請碼（`secrets.token_hex(4).upper()`）
  - 建立者自動加入為 primary family_member
- [ ] `GET /families/:id` — 取得家庭資訊 + 成員列表（Nested Serializer）
- [ ] `POST /families/:id/members` — 透過邀請碼加入
- [ ] `DELETE /families/:id/members/:userId` — 移除成員

---

## Phase 3：即時通訊

### 3.1 聊天 REST API（功能 4.1–4.7）

- [ ] `GET /chats` — 聊天室列表（含未讀計數，`annotate` + Redis）
- [ ] `POST /chats` — 建立聊天室（group / direct）
- [ ] `GET /chats/:id/messages` — 歷史訊息（cursor-based 分頁 `CursorPagination`）
- [ ] `POST /chats/:id/messages` — 發送訊息（HTTP fallback）
  - 文字訊息：呼叫翻譯服務 → 存入翻譯結果
  - 圖片訊息：上傳 S3 → 儲存 URL

### 3.2 WebSocket 即時通訊（Django Channels）

- [ ] `ChatConsumer(AsyncWebsocketConsumer)` — WebSocket Consumer
  - `connect()`：Token 驗證、加入 Channel Group
  - `receive()`：接收訊息 → 翻譯 → 存入 DB → 廣播
  - `disconnect()`：離開 Channel Group
- [ ] Channel Layer 設定（`channels_redis.core.RedisChannelLayer`）
- [ ] 事件處理：
  - `chat.message`：訊息廣播
  - `chat.typing`：「正在輸入」狀態轉發
- [ ] ASGI routing（`routing.py`）：

```python
websocket_urlpatterns = [
    re_path(r'ws/chat/(?P<chat_id>\w+)/$', ChatConsumer.as_asgi()),
]
```

- [ ] 離線訊息處理：WebSocket 斷線時觸發 APNs 推播

### 3.3 翻譯服務（功能 3.2–3.3）

- [ ] `POST /translate` — 文字翻譯
- [ ] `POST /translate/speech` — 語音轉文字 + 翻譯
- [ ] 翻譯服務封裝（`core/translation.py`）：
  - OpenAI API 翻譯（使用 `openai` SDK）
  - 翻譯快取（Redis，相同文字+語言對不重複翻譯）

---

## Phase 4：照護核心 API

### 4.1 照護日誌 API（功能 6.1–6.7）

- [ ] `GET /care-logs` — 時間軸查詢
  - `django-filter` 支援類型篩選、日期區間
  - 分頁（`PageNumberPagination`）
- [ ] `POST /care-logs` — 新增紀錄
  - 支援 5 種類型：medication / vital / meal / activity / note
  - 照片附件上傳至 S3（`django-storages`）
  - 文字內容自動翻譯（Celery 背景任務）
- [ ] `PUT /care-logs/:id` — 更新紀錄
- [ ] `GET /care-logs/summary` — 照護摘要
  - Django ORM `aggregate` / `annotate` 計算：
    - 用藥順從度（confirmed / total）
    - 生理平均值（`Avg`）
    - 飲食統計（`Count` by appetite）
    - 活動統計

### 4.2 用藥管理 API（功能 7.1–7.6）

- [ ] `GET /medications` — 藥物清單（`ModelViewSet`）
- [ ] `POST /medications` — 新增藥物
  - 自動翻譯藥物名稱與說明
  - 建立用藥提醒排程（寫入 `calendar_event`，type: medication）
- [ ] `PUT /medications/:id` — 更新藥物
- [ ] `POST /medications/:id/confirm` — 餵藥拍照確認
  - 照片上傳 S3
  - **自動建立 `care_log` 用藥紀錄**（跨模組連動）
  - Celery 任務：推播通知家屬
- [ ] **Celery Beat 定時任務**：用藥提醒排程
  - 每分鐘檢查 → 到達時間的藥物 → APNs 推播看護 + Watch

### 4.3 健康監測 API（功能 10.1–10.8）

- [ ] `POST /health/sync` — Watch 健康數據批次同步
  - 去重處理（`get_or_create` 或 `unique_together`）
  - **即時異常檢測**：比對閾值 → 觸發警示
  - 異常時 Celery 任務推播通知所有家庭成員
- [ ] `GET /health/data` — 歷史數據查詢
  - 支援 `raw` / `hourly` / `daily` 聚合
  - Django ORM：`TruncHour` / `TruncDay` + `Avg` / `Min` / `Max`
- [ ] `GET /health/dashboard` — 儀表板彙總
- [ ] `GET /health/alerts` — 異常警示紀錄
- [ ] `PUT /health/alerts/:id/acknowledge` — 確認警示
- [ ] `PUT /health/thresholds` — 更新異常閾值

### 4.4 消費記帳 API（功能 8.1–8.5）

- [ ] `POST /expenses/scan` — 收據 OCR（非同步處理）
  - 接收收據照片 → 上傳 S3
  - 回應 202 Accepted
  - **Celery 背景任務**：
    1. OpenAI GPT-4o Vision 圖片辨識（直接發送圖片 base64 給 GPT-4o Vision）
    2. GPT-4o 結構化解析為 JSON（品名、數量、金額、日期、分類）
    3. 儲存結果至 DB
    4. APNs 推播通知前端
- [ ] `GET /expenses/:id` — 取得單筆
- [ ] `GET /expenses` — 列表（`django-filter`：日期/分類）
- [ ] `PUT /expenses/:id` — 修正 OCR 結果
- [ ] `GET /expenses/monthly` — 月結帳單
  - Django ORM 聚合：`Sum`、`Count`，按 category/date group by

---

## Phase 5：輔助功能 API

### 5.1 留言板 API（功能 5.1–5.4）

- [ ] `ModelViewSet` for BoardRequest（CRUD）
  - 新增時：品項自動翻譯 + 推播通知家屬
  - 確認/駁回時：推播通知看護

### 5.2 請假管理 API（功能 9.1–9.4）

- [ ] `ModelViewSet` for Leave（CRUD）
  - 申請時：原因自動翻譯 + 推播通知家屬
  - 核准時：**自動建立 `calendar_event`**（跨模組連動）+ 推播通知看護

### 5.3 行事曆 + 代辦 API（功能 11–12）

- [ ] `ModelViewSet` for Event（CRUD）
  - 標題自動翻譯
- [ ] `ModelViewSet` for Todo（CRUD）
  - 新增時推播通知被指派者
  - 完成時**自動建立 `care_log` 活動紀錄**（跨模組連動）
- [ ] **Celery Beat 定時任務**：行程提醒
  - 每分鐘檢查 → 行程前 N 分鐘 → APNs 推播

### 5.4 文件管理 API（功能 13.1–13.4）

- [ ] `POST /documents` — 上傳文件（multipart → S3 via `django-storages`）
  - 檔案大小限制 10MB（`DATA_UPLOAD_MAX_MEMORY_SIZE`）
- [ ] `GET /documents` — 列表（`django-filter`：category）
- [ ] `GET /documents/:id` — Presigned URL（`boto3 generate_presigned_url`，1 hr）
- [ ] `DELETE /documents/:id` — 刪除（DB + S3）

---

## Phase 6：AI 功能整合

### 6.1 AI 智慧助理（功能 14.1–14.6）

- [ ] `POST /ai/chat` — 對話式查詢（SSE 串流回應）

```python
from openai import OpenAI

client = OpenAI()

# Function Calling tools 定義
tools = [
    {"name": "query_health_data", "description": "查詢健康數據", "input_schema": {...}},
    {"name": "query_care_logs", "description": "查詢照護日誌", "input_schema": {...}},
    {"name": "query_medications", "description": "查詢用藥紀錄", "input_schema": {...}},
    {"name": "query_expenses", "description": "查詢消費紀錄", "input_schema": {...}},
    {"name": "query_events", "description": "查詢行事曆", "input_schema": {...}},
]

# SSE 串流回應
def ai_chat_view(request):
    response = StreamingHttpResponse(
        stream_openai_response(message, tools, conversation),
        content_type='text/event-stream'
    )
    return response
```

- [ ] Function Calling 工具實作：
  - 每個 tool 對應 Django ORM 查詢
  - 查詢結果回傳給 GPT-4o → GPT-4o 生成最終回應
- [ ] 對話歷史管理（`AIConversation` Model）
- [ ] **個資保護**：在 system prompt 中嚴格限制不回傳敏感資訊

- [ ] `POST /ai/care-analysis` — 照護記錄分析
  - 取得照護摘要（`GET /care-logs/summary` 內部呼叫）
  - `openai` SDK 呼叫 GPT-4o → 產生分析報告
- [ ] `POST /ai/handover-report` — 看護交接報告
  - 彙整資料 → GPT-4o 生成雙語報告
  - 選用：`reportlab` 生成 PDF → S3
- [ ] `POST /ai/subsidy-form` — 政府補助表單
  - GPT-4o 根據長者資料填寫 → 標記缺漏欄位
  - `reportlab` 生成 PDF → S3

### 6.2 AI 急救小幫手 — RAG（功能 15.1–15.4）

- [ ] `POST /ai/first-aid` — 急救指引查詢

```python
from openai import OpenAI
from pgvector.django import VectorField, L2Distance

client = OpenAI()

# 1. 使用者查詢 → Embedding
query_embedding = client.embeddings.create(
    input=[query], model="text-embedding-3-small"
).data[0].embedding

# 2. pgvector 相似度搜尋
results = FirstAidDocument.objects.order_by(
    L2Distance('embedding', query_embedding)
)[:5]

# 3. OpenAI GPT-4o 生成急救指引
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[
        {"role": "system", "content": "你是急救指引助手，僅基於以下衛福部文件回答..."},
        {"role": "user", "content": f"文件：{context}\n問題：{query}"}
    ]
)
```

- [ ] RAG 資料準備：
  - [ ] 蒐集衛福部急救手冊、用藥指南 PDF
  - [ ] 文件分段（chunking）— 使用 `langchain.text_splitter` 或手動分段
  - [ ] OpenAI Embedding API 轉為向量
  - [ ] Django management command 批次寫入 pgvector
- [ ] `FirstAidDocument` Model（含 `VectorField`）

---

## Phase 7：推播通知系統

### 7.1 APNs 整合

- [ ] APNs 推播服務封裝（`core/apns.py`）：

```python
from apns2.client import APNsClient
from apns2.payload import Payload

client = APNsClient(
    credentials='/path/to/AuthKey.p8',
    use_sandbox=True  # 開發環境
)

def send_push(device_token, title, body, data=None):
    payload = Payload(alert={"title": title, "body": body}, custom=data, sound="default")
    client.send_notification(device_token, payload, topic='com.carebridge.app')
```

- [ ] `POST /notifications/device` — 註冊裝置 Token
- [ ] `GET /notifications` — 通知列表（分頁、已讀篩選）
- [ ] `PUT /notifications/:id/read` — 標記已讀
- [ ] `PUT /notifications/read-all` — 全部已讀
- [ ] 通知建立 + 推播統一封裝（`core/apns.py`）：
  - 建立 `Notification` DB 紀錄
  - 翻譯標題/內容
  - 查詢使用者裝置 Token
  - 呼叫 APNs 發送
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
  - **同步**推播通知所有家庭成員（高優先級 APNs，`priority=10`）
- [ ] `GET /sos/history` — SOS 歷史紀錄

---

## Phase 9：檔案儲存服務

### 9.1 AWS S3 整合

- [ ] `django-storages` 設定（`settings.py`）：

```python
DEFAULT_FILE_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'
AWS_STORAGE_BUCKET_NAME = 'carebridge-storage'
AWS_S3_REGION_NAME = 'ap-northeast-1'
AWS_QUERYSTRING_AUTH = True  # Presigned URL
AWS_QUERYSTRING_EXPIRE = 3600  # 1 小時
```

- [ ] S3 Bucket 結構：

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

- [ ] Presigned URL 生成（`boto3`）：

```python
import boto3
s3 = boto3.client('s3')
url = s3.generate_presigned_url('get_object',
    Params={'Bucket': 'carebridge-storage', 'Key': key},
    ExpiresIn=3600
)
```

- [ ] 圖片壓縮處理（Pillow，上傳前壓縮至合理大小）
- [ ] 檔案大小限制驗證（10MB）

---

## Phase 10：部署與 DevOps

### 10.1 部署準備

- [ ] Production Dockerfile（multi-stage build）：

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN python manage.py collectstatic --noinput
CMD ["gunicorn", "carebridge_api.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000"]
```

- [ ] `docker-compose.production.yml`：
  - Django (Gunicorn + Uvicorn)
  - PostgreSQL（含備份 volume）
  - Redis
  - Celery Worker + Beat
  - Nginx
- [ ] Nginx 設定（反向代理 + SSL + WebSocket Upgrade + 靜態檔案）
- [ ] SSL 憑證（Let's Encrypt / Certbot）
- [ ] AWS EC2 / GCP Cloud Run 部署

### 10.2 CI/CD

- [ ] GitHub Actions workflow：
  - `pip install` + `python manage.py test`
  - Docker build + push
  - 自動部署到 staging
- [ ] 健康檢查端點（`GET /health`）

### 10.3 監控與日誌

- [ ] Django Logging 設定（JSON format）
- [ ] Sentry 或同類錯誤追蹤（選用）
- [ ] Django Debug Toolbar（開發環境）

---

## Phase 11：測試

- [ ] 單元測試：所有 Service 層業務邏輯（`django.test.TestCase`）
- [ ] API 整合測試：DRF `APITestCase`（所有端點）
- [ ] WebSocket 測試：Channels `WebsocketCommunicator`
- [ ] Celery 任務測試：`CELERY_ALWAYS_EAGER = True`（同步測試模式）
- [ ] 負載測試：健康數據同步 API（高頻寫入場景）

---

## 跨模組自動連動（後端需特別處理）

以下功能涉及跨模組資料寫入，建議在對應的 ViewSet / Serializer 中統一實作：

| 觸發動作 | 自動建立 | 實作位置 |
|---|---|---|
| 餵藥拍照確認（7.4） | 照護日誌 - 用藥紀錄（6.3） | `medication/views.py → MedicationConfirmView` |
| 完成代辦（12.3） | 照護日誌 - 活動紀錄（6.6） | `todo/views.py → TodoViewSet.partial_update()` |
| 請假核准（9.2） | 行事曆事件（11） | `leave/views.py → LeaveViewSet.partial_update()` |
| 新增藥物 + 開啟提醒（7.2） | 行事曆用藥事件（11.3） | `medication/views.py → MedicationViewSet.create()` |
| 健康數據異常（10.1） | 健康警示紀錄（10.7）+ 推播 | `health/views.py → HealthSyncView.post()` |

---

## 前後端協作約定

| 項目 | 規範 |
|---|---|
| Base URL | `https://api.carebridge.app/v1`（Production）/ `http://localhost:8000/v1`（Dev） |
| 認證 | `Authorization: Bearer {access_token}` |
| Content-Type | `application/json`（預設）/ `multipart/form-data`（檔案上傳） |
| 日期格式 | ISO 8601（`2026-04-08T14:30:00Z`） |
| 分頁 | `?page=1&limit=20`（預設 20 筆） |
| 錯誤格式 | `{ success: false, error: { code, message, details } }` |
| WebSocket | `wss://api.carebridge.app/v1/ws/chat/{id}?token={token}` |
| SSE | `Content-Type: text/event-stream`（AI 串流） |
| Django Admin | `https://api.carebridge.app/admin/`（開發/Demo 用資料管理後台） |
