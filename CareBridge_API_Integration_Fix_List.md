# CareBridge API Integration Fix List

> **更新日期**: 2026-04-13（第二版，根據 main 最新程式碼重新審查）
> **目的**: 整理目前 CareBridge 前端、後端、API 文件三者不一致之處，作為修正與驗收清單
> **審查基準**: `main` branch @ `ecc6b68`

---

## 0. 整體結論

- **後端完成度約 85%** — 15 個模組的 CRUD + AI + 推播 + SOS 全部實作完畢
- **前後端串接度約 60%** — 列表讀取多數已接通，但寫入/審核/上傳/AI 串流仍有缺口
- **關鍵阻斷問題 5 個**（P0）— 會導致功能完全無法使用
- **功能缺口 10 個**（P1）— 功能不完整但不會 crash
- **待完善項目 8 個**（P2）— 品質/DevOps/測試

---

## 1. P0 — 立即修正（Demo 會壞）

### 1.1 `[CRITICAL]` Join Family 路徑 404

| 項目 | 內容 |
|------|------|
| **前端呼叫** | `POST /auth/join-family/` (`APIDataService.swift:90`) |
| **後端實際路徑** | `POST /families/<pk>/join/` (需要先知道 family pk) |
| **API 文件** | `POST /families/:id/members/` (第三種寫法) |
| **問題** | 三方路徑完全不同，前端會收到 **404** |
| **影響** | 加入家庭功能完全無法使用 |
| **建議修復** | 後端新增 `POST /auth/join-family/`，接收 `{"invite_code": "XXXX"}`，透過 invite_code 查詢 Family 並加入，回傳 `AuthResponse {user, tokens}` 格式 |

涉及檔案:
- `CareBridge/Services/APIDataService.swift:89-95`
- `CareBridge/Views/Auth/JoinFamilyView.swift:211-229`
- `backend/apps/family/views.py:100-118`
- `backend/apps/auth_account/urls.py`

### 1.2 `[CRITICAL]` Join Family 回傳格式不匹配

| 項目 | 內容 |
|------|------|
| **前端預期** | `AuthResponse { user: UserProfile, tokens: AuthTokens }` |
| **後端回傳** | `FamilySerializer` 格式（Family 資料，非 AuthResponse） |
| **影響** | 即使路徑修正後，Swift JSON 解碼仍會失敗 |

### 1.3 `[CRITICAL]` First Aid HTTP Method 不匹配

| 項目 | 內容 |
|------|------|
| **前端呼叫** | `GET /ai/first-aid/` (`APIDataService.swift:206`，用 `get` method) |
| **後端** | `POST /ai/first-aid/`（`FirstAidView` 只接受 POST） |
| **前端預期回傳** | `[FirstAidScenario]` 陣列 |
| **後端回傳** | `{ answer, sources, tokens_used }` 單一物件 |
| **影響** | 前端收到 **405 Method Not Allowed** |
| **建議修復** | 方案 A: 後端增加 `GET` handler 回傳預設急救場景列表 + 保留 `POST` 做 RAG 查詢；方案 B: 前端改用 POST |

涉及檔案:
- `CareBridge/Services/APIDataService.swift:206`
- `CareBridge/Views/AI/FirstAidView.swift`
- `backend/apps/ai_assistant/views.py:539-693`

### 1.4 `[BUG]` Weekly Steps 回傳格式不匹配

| 項目 | 內容 |
|------|------|
| **前端預期** | `[Int]` 純整數陣列 (`DataService.swift:47`) |
| **後端回傳** | `[{"date": "2026-04-07", "total_steps": 8500}, ...]` 物件陣列 |
| **影響** | JSON 解碼失敗，步數圖表無法顯示 |
| **建議修復** | 前端改 model 為 `[WeeklyStepEntry]`，或後端新增簡化回傳格式 |

涉及檔案:
- `CareBridge/Services/DataService.swift:47`
- `CareBridge/Services/APIDataService.swift:110`
- `backend/apps/health/views.py:219-251`

### 1.5 `[BUG]` Spending Summary 回傳格式不匹配

| 項目 | 內容 |
|------|------|
| **前端預期** | `SpendingSummary { monthlyTotal: Double, categoryBreakdown: [CategoryBreakdownItem] }` |
| **後端回傳** | `[{month, total_amount, count}]` 月份陣列（無分類統計） |
| **影響** | JSON 解碼失敗，消費統計頁面崩潰 |
| **建議修復** | 後端增加 category 分組統計欄位，或前端改 model 對應 |

涉及檔案:
- `CareBridge/Services/DataService.swift:23-31`
- `CareBridge/Services/APIDataService.swift:140`
- `backend/apps/expense/views.py:112-146`

---

## 2. P1 — 高優先修正（功能不完整）

### 2.1 `[MISSING]` AI Chat SSE 串流協定不一致

| 項目 | 內容 |
|------|------|
| **前端** | `AIAgentView` 預期 `{"type":"token","content":"..."}` 格式 |
| **後端** | 實際送出 `{"type":"content","text":"..."}` |
| **問題** | field name 不同（`content` vs `text`），event type 不同（`token` vs `content`） |
| **影響** | AI 串流回覆無法逐字顯示 |
| **修復** | 統一 SSE payload 格式，前端需加 `?stream=true` |

涉及檔案:
- `CareBridge/Views/AI/AIAgentView.swift`
- `backend/apps/ai_assistant/views.py:147-191`

### 2.2 `[MISSING]` Celery Beat 排程未設定

| 項目 | 內容 |
|------|------|
| **現況** | `settings/base.py` 缺少 `CELERY_BEAT_SCHEDULE` 設定 |
| **影響** | `send_medication_reminders()` 定時任務永遠不會自動執行 |
| **修復** | 在 `base.py` 加入 Celery Beat 排程 |

```python
# 需要加入的設定
CELERY_BEAT_SCHEDULE = {
    'medication-reminders': {
        'task': 'apps.notification.tasks.send_medication_reminders',
        'schedule': crontab(minute='*/15'),
    },
}
```

涉及檔案:
- `backend/carebridge_api/settings/base.py:193-201`
- `backend/apps/notification/tasks.py:75`

### 2.3 `[MISSING]` Expense OCR Celery Task 未實作

| 項目 | 內容 |
|------|------|
| **現況** | `POST /expenses/scan/` 建立 `status='processing'` 後回傳 202，無後續處理 |
| **缺少** | 沒有 Celery task 呼叫 GPT-4o Vision 解析收據圖片 |
| **影響** | 掃描收據永遠停在 processing 狀態 |
| **修復** | 新增 `apps/expense/tasks.py`，用 OpenAI Vision 解析圖片後更新 Expense |

涉及檔案:
- `backend/apps/expense/views.py:93-110`

### 2.4 `[MISSING]` Password Reset / Forgot Password 未實作

| 項目 | 內容 |
|------|------|
| **前端** | `LoginView.swift:10` 有 `showForgotPassword` state |
| **後端** | 無 `POST /auth/forgot-password/` 和 `POST /auth/reset-password/` |
| **文件** | API 文件有列出，serializer 已寫好但 view 和 url 未掛出 |

涉及檔案:
- `CareBridge/Views/Auth/LoginView.swift:10`
- `backend/apps/auth_account/urls.py`
- `backend/apps/auth_account/serializers.py`

### 2.5 `[MISSING]` 前端缺少 Register 頁面

| 項目 | 內容 |
|------|------|
| **後端** | `POST /auth/register/` 已實作完畢 |
| **前端** | 沒有 RegisterView，LoginView 無導向註冊的入口 |
| **影響** | 使用者無法從 App 內建立新帳號 |

### 2.6 `[MISMATCH]` 個人資料頁只有 UI，未真正串接後端

| 項目 | 操作 | 前端現況 | 後端 |
|------|------|---------|------|
| 編輯個資 | PUT /auth/me/ | 只做 `dismiss()` | ✅ 已實作 |
| 登出 | POST /auth/logout/ | 只改 `isLoggedIn = false` | ✅ 已實作 |
| 刪除帳號 | DELETE /auth/account/ | 按鈕沒有實作 | ✅ 已實作 |

涉及檔案:
- `CareBridge/Views/Shared/ProfileView.swift`
- `CareBridge/Services/APIDataService.swift:97-106`

### 2.7 `[MISMATCH]` 多個前端頁面「寫入操作」未呼叫後端

| 模組 | 操作 | 前端狀態 | 後端 |
|------|------|---------|------|
| 文件管理 | 上傳/刪除 | 只改本地陣列 | ✅ API 存在 |
| 請假管理 | 送出申請/審核 | 只改本地 state | ✅ API 存在 |
| 留言板 | 新增需求/審核 | 只改本地 state | ✅ API 存在 |
| 消費記帳 | 新增支出 | 插入本地陣列 | ✅ API 存在 |
| SOS | 觸發 SOS | 只撥打 119 | ✅ API 存在 |

涉及檔案:
- `CareBridge/Views/Document/DocumentsView.swift`
- `CareBridge/Views/Leave/LeaveManagementView.swift`
- `CareBridge/Views/Board/MessageBoardView.swift`
- `CareBridge/Views/Spending/SpendingView.swift`
- `CareBridge/Views/SOS/SOSView.swift`

### 2.8 `[MISMATCH]` AI Chat 回傳格式待確認

| 項目 | 內容 |
|------|------|
| **前端預期** | `AIMessage` 型別 |
| **後端回傳** | `{conversation_id, reply, tokens_used}` |
| **需確認** | `AppModels.swift` 中 `AIMessage` 的欄位名稱是否與後端一致 |

### 2.9 `[TODO]` 通知 type enum 前後端不一致

| 項目 | 內容 |
|------|------|
| **後端實際送出的 type** | `sos`, `sos_resolved`, `leave_status`, `health_alert`, `chat_message`, `medication_reminder` |
| **前端 enum** | 未完整涵蓋所有後端 type |
| **影響** | 未知 type 可能導致 enum decode 失敗，通知列表整頁崩潰 |

涉及檔案:
- `CareBridge/Models/AppModels.swift`
- `backend/core/notify.py`
- `backend/apps/notification/tasks.py`

### 2.10 `[TODO]` Token Refresh 未實作

| 項目 | 內容 |
|------|------|
| **現況** | Keychain 有存 refresh token，但 APIDataService 沒有 401 自動 refresh 流程 |
| **影響** | Access token 1 小時過期後，使用者需重新登入 |

涉及檔案:
- `CareBridge/Services/APIDataService.swift:26-55`
- `CareBridge/Services/KeychainService.swift`

---

## 3. P2 — 中優先修正（品質/完善）

### 3.1 `[TODO]` 留言板審核通知

- `board/views.py` 的 `update_status` 未觸發推播通知
- 代購請求被批准/拒絕時，申請人不會收到推播

### 3.2 `[TODO]` 通知多語翻譯

- Notification model 有 `title_translated` / `body_translated` 欄位
- `core/notify.py` 建立通知時沒有呼叫翻譯
- 外籍看護收到的通知只有中文

### 3.3 `[TODO]` 健康監測畫面未接後端

- `HealthMonitorView` 主要使用本地 `HealthKitManager`
- 後端 `health-data/dashboard`、`alerts`、`thresholds` API 存在但前端未呼叫
- 需決定 HealthKit 與後端資料的主從關係

### 3.4 `[TODO]` 生物辨識登入是假登入

- 目前使用 hardcoded `mock@carebridge.com / mock` 帳號
- 應改為使用 Keychain 已存的 token 做 silent login

涉及檔案:
- `CareBridge/Views/Auth/LoginView.swift:236`

### 3.5 `[TODO]` pgvector 未啟用

- `FirstAidDocument.embedding` 仍是 TextField 而非 pgvector VectorField
- 開發階段有 in-memory cosine similarity fallback，但生產環境需遷移

### 3.6 `[TODO]` 急救文件載入工具

- `FirstAidDocument` model 存在，但沒有 management command 匯入文件和生成 embedding
- RAG 功能需要有資料才能運作

### 3.7 `[TODO]` 測試全空

- 15 個 app 的 `tests.py` 全部只有 placeholder
- 零實際測試覆蓋率

### 3.8 `[TODO]` CI/CD 未設定

- 沒有 GitHub Actions workflow
- Docker 設定已有但無自動化部署流程

---

## 4. 前後端 API 路徑完整對照表

| 前端路徑 | Method | 後端路徑 | 狀態 |
|----------|--------|---------|------|
| `/auth/login/` | POST | `/auth/login/` | ✅ 一致 |
| `/auth/join-family/` | POST | `/families/<pk>/join/` | ❌ 路徑不匹配 (1.1) |
| `/auth/logout/` | POST | `/auth/logout/` | ✅ 一致 |
| `/auth/me/` | GET/PUT | `/auth/me/` | ✅ 一致 |
| `/families/members/` | GET | `/families/members/` | ✅ 一致 |
| `/health-data/dashboard/` | GET | `/health-data/dashboard` | ✅ 一致 |
| `/health-data/weekly-steps/` | GET | `/health-data/weekly-steps` | ⚠️ 路徑一致，回傳格式不匹配 (1.4) |
| `/chats/` | GET | `/chats/` | ✅ 一致 |
| `/chats/{id}/messages/` | GET/POST | `/chats/{id}/messages/` | ✅ 一致 |
| `/care-logs/` | GET/POST | `/care-logs/` | ✅ 一致 |
| `/medications/` | GET/POST/PUT | `/medications/` | ✅ 一致 |
| `/medications/today_confirmations` | GET | `/medications/today_confirmations` | ✅ 一致 |
| `/medications/{id}/confirm` | POST | `/medications/{id}/confirm` | ✅ 一致 |
| `/expenses/` | GET/POST | `/expenses/` | ✅ 一致 |
| `/expenses/monthly/` | GET | `/expenses/monthly` | ⚠️ 路徑一致，回傳格式不匹配 (1.5) |
| `/todos/` | GET/POST | `/todos/` | ✅ 一致 |
| `/todos/{id}/` | PUT | `/todos/{id}/` | ✅ 一致 |
| `/events/` | GET/POST | `/events/` | ✅ 一致 |
| `/events/batch/` | POST | `/events/batch/` | ✅ 一致 |
| `/leaves/` | GET/POST | `/leaves/` | ✅ 一致 |
| `/leaves/{id}/status/` | PATCH | `/leaves/{id}/status/` | ✅ 一致 |
| `/documents/` | GET/POST | `/documents/` | ✅ 一致 |
| `/documents/{id}/` | DELETE | `/documents/{id}/` | ✅ 一致 |
| `/notifications/` | GET | `/notifications/` | ✅ 一致 |
| `/notifications/{id}/read/` | PUT | `/notifications/{id}/read/` | ✅ 一致 |
| `/notifications/device/` | POST | `/notifications/device/` | ✅ 一致 |
| `/board/` | GET/POST | `/board/` | ✅ 一致 |
| `/board/{id}/status/` | PATCH | `/board/{id}/status/` | ✅ 一致 |
| `/ai/chat/` | POST | `/ai/chat/` | ⚠️ 路徑一致，SSE 格式不匹配 (2.1) |
| `/ai/first-aid/` | **GET** | `/ai/first-aid/` (**POST** only) | ❌ Method 不匹配 (1.3) |
| `/sos/trigger/` | POST | `/sos/trigger/` | ✅ 一致 |

---

## 5. 建議修正順序

### 第一波：修復阻斷問題（P0，預計 1-2 天）
1. 後端新增 `POST /auth/join-family/` endpoint
2. 後端 First Aid 新增 GET handler
3. 修正 Weekly Steps / Spending Summary 回傳格式（前端或後端擇一修改）

### 第二波：補齊寫入串接（P1，預計 2-3 天）
4. 統一 AI SSE 串流格式
5. 前端各頁面寫入操作接上後端 API
6. 加入 Celery Beat 排程
7. 實作 Expense OCR Celery task
8. 對齊通知 type enum

### 第三波：完善品質（P2，預計 3-5 天）
9. Token auto-refresh
10. Password reset 流程
11. 註冊頁面
12. 通知翻譯
13. 基本 API 測試

---

## 6. 驗收清單

- [ ] 前端不再呼叫不存在的 API（零 404/405）
- [ ] 加入家庭流程可成功完成
- [ ] AI Chat SSE 可正常逐字顯示
- [ ] 所有有 UI 按鈕的新增/更新/刪除/審核動作都打到後端
- [ ] 通知列表可載入真資料而不 decode fail
- [ ] 健康頁步數圖表正確顯示
- [ ] 消費統計頁面正確顯示
- [ ] 用藥提醒定時任務正常觸發
- [ ] API 文件、前端、後端三方路徑一致
