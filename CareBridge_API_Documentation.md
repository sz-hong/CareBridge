# CareBridge 照護橋 — Backend API 規格文件

> **Base URL**: `https://api.carebridge.app/v1`
> **認證方式**: Bearer Token（JWT）
> **Content-Type**: `application/json`（除非特別標注 `multipart/form-data`）
> **日期格式**: ISO 8601（`2026-04-08T14:30:00Z`）
> **分頁參數**: `?page=1&limit=20`（預設 20 筆/頁）

---

## 通用回應格式

### 成功回應

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "page": 1,
    "limit": 20,
    "total": 58
  }
}
```

### 錯誤回應

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "欄位驗證失敗",
    "details": [
      { "field": "email", "message": "email 格式不正確" }
    ]
  }
}
```

### 通用錯誤碼

| HTTP Status | Code | 說明 |
|---|---|---|
| 400 | `VALIDATION_ERROR` | 請求參數驗證失敗 |
| 401 | `UNAUTHORIZED` | 未提供或無效的 Token |
| 403 | `FORBIDDEN` | 無權限存取該資源 |
| 404 | `NOT_FOUND` | 資源不存在 |
| 409 | `CONFLICT` | 資源衝突（如重複註冊） |
| 429 | `RATE_LIMITED` | 請求過於頻繁 |
| 500 | `INTERNAL_ERROR` | 伺服器內部錯誤 |

---

## 1. Auth 認證

### POST /auth/register

註冊新帳號。

**Request Body**:
```json
{
  "email": "caregiver@example.com",
  "password": "securePassword123",
  "name": "Siti Nurhaliza",
  "role": "caregiver",
  "language": "id",
  "phone": "+886912345678"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| email | string | ✅ | 電子郵件 |
| password | string | ✅ | 密碼（至少 8 碼） |
| name | string | ✅ | 姓名 |
| role | enum | ✅ | `caregiver` / `family_member` / `elder` |
| language | enum | ✅ | `zh-TW` / `id` / `vi` / `tl`（印尼/越南/菲律賓語） |
| phone | string | ⬜ | 電話號碼 |

**Response 201**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "usr_abc123",
      "email": "caregiver@example.com",
      "name": "Siti Nurhaliza",
      "role": "caregiver",
      "language": "id"
    },
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

---

### POST /auth/login

登入取得 Token。

**Request Body**:
```json
{
  "email": "caregiver@example.com",
  "password": "securePassword123"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "usr_abc123",
      "email": "caregiver@example.com",
      "name": "Siti Nurhaliza",
      "role": "caregiver",
      "language": "id",
      "family_id": "fam_xyz789"
    },
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

---

### POST /auth/refresh

刷新 Access Token。

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 3600
  }
}
```

---

### GET /auth/me

取得目前登入者資訊。

**Headers**: `Authorization: Bearer {access_token}`

**Response 200**:
```json
{
  "success": true,
  "data": {
    "id": "usr_abc123",
    "email": "caregiver@example.com",
    "name": "Siti Nurhaliza",
    "role": "caregiver",
    "language": "id",
    "phone": "+886912345678",
    "family_id": "fam_xyz789",
    "avatar_url": null,
    "created_at": "2026-04-01T08:00:00Z"
  }
}
```

---

## 2. Family 家庭管理

### POST /families

建立家庭群組。

**Request Body**:
```json
{
  "name": "王家照護群組",
  "elder_name": "王大明",
  "elder_birth_date": "1945-03-15"
}
```

**Response 201**:
```json
{
  "success": true,
  "data": {
    "id": "fam_xyz789",
    "name": "王家照護群組",
    "elder_name": "王大明",
    "invite_code": "CARE-A3B7",
    "created_at": "2026-04-01T08:00:00Z"
  }
}
```

---

### GET /families/:id

取得家庭資訊與成員列表。

**Response 200**:
```json
{
  "success": true,
  "data": {
    "id": "fam_xyz789",
    "name": "王家照護群組",
    "elder_name": "王大明",
    "members": [
      {
        "id": "usr_abc123",
        "name": "Siti Nurhaliza",
        "role": "caregiver",
        "language": "id",
        "joined_at": "2026-04-01T10:00:00Z"
      },
      {
        "id": "usr_def456",
        "name": "王小華",
        "role": "family_member",
        "language": "zh-TW",
        "is_primary": true,
        "joined_at": "2026-04-01T08:00:00Z"
      }
    ],
    "invite_code": "CARE-A3B7"
  }
}
```

---

### POST /families/:id/members

透過邀請碼加入家庭。

**Request Body**:
```json
{
  "invite_code": "CARE-A3B7"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "family_id": "fam_xyz789",
    "user_id": "usr_ghi789",
    "role": "family_member",
    "joined_at": "2026-04-02T09:00:00Z"
  }
}
```

---

### PUT /users/:id

更新個人檔案（語言偏好、頭像等）。

**Request Body**:
```json
{
  "name": "Siti Nurhaliza",
  "language": "id",
  "phone": "+886912345678",
  "avatar_url": "https://storage.carebridge.app/avatars/usr_abc123.jpg"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "id": "usr_abc123",
    "name": "Siti Nurhaliza",
    "language": "id",
    "phone": "+886912345678",
    "avatar_url": "https://storage.carebridge.app/avatars/usr_abc123.jpg",
    "updated_at": "2026-04-08T14:30:00Z"
  }
}
```

---

## 3. Chat 即時聊天

### GET /chats

取得聊天室列表。

**Query Parameters**: `?family_id=fam_xyz789`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "chat_001",
      "type": "group",
      "name": "王家照護群",
      "family_id": "fam_xyz789",
      "last_message": {
        "text": "爸爸今天血壓正常",
        "translated_text": "Tekanan darah ayah hari ini normal",
        "sender_id": "usr_def456",
        "sent_at": "2026-04-08T10:30:00Z"
      },
      "unread_count": 3
    }
  ]
}
```

---

### POST /chats

建立聊天室。

**Request Body**:
```json
{
  "type": "direct",
  "family_id": "fam_xyz789",
  "member_ids": ["usr_abc123", "usr_def456"]
}
```

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| type | enum | ✅ | `group`（全家）/ `direct`（一對一） |
| family_id | string | ✅ | 家庭 ID |
| member_ids | array | ⬜ | `direct` 時必填 |

**Response 201**:
```json
{
  "success": true,
  "data": {
    "id": "chat_002",
    "type": "direct",
    "members": ["usr_abc123", "usr_def456"],
    "created_at": "2026-04-08T14:00:00Z"
  }
}
```

---

### GET /chats/:id/messages

取得歷史訊息（分頁，由新到舊）。

**Query Parameters**: `?page=1&limit=50&before=2026-04-08T14:00:00Z`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "msg_001",
      "chat_id": "chat_001",
      "sender_id": "usr_def456",
      "type": "text",
      "content": {
        "text": "爸爸今天血壓正常",
        "translated": {
          "id": "Tekanan darah ayah hari ini normal",
          "vi": "Huyết áp của bố hôm nay bình thường"
        }
      },
      "sent_at": "2026-04-08T10:30:00Z"
    },
    {
      "id": "msg_002",
      "chat_id": "chat_001",
      "sender_id": "usr_abc123",
      "type": "image",
      "content": {
        "image_url": "https://storage.carebridge.app/chat/msg_002.jpg",
        "caption": "Sudah minum obat pagi",
        "translated": {
          "zh-TW": "早上的藥已經吃了"
        }
      },
      "sent_at": "2026-04-08T10:35:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 50, "total": 128 }
}
```

---

### POST /chats/:id/messages

發送訊息（HTTP fallback，主要走 WebSocket）。

**Request Body（文字）**:
```json
{
  "type": "text",
  "text": "Sudah makan siang"
}
```

**Request Body（圖片，multipart/form-data）**:
| 欄位 | 型別 | 說明 |
|---|---|---|
| type | string | `image` |
| image | file | 圖片檔案 |
| caption | string | 圖片說明（選填） |

**Response 201**:
```json
{
  "success": true,
  "data": {
    "id": "msg_003",
    "chat_id": "chat_001",
    "type": "text",
    "content": {
      "text": "Sudah makan siang",
      "translated": {
        "zh-TW": "已經吃過午餐了"
      }
    },
    "sent_at": "2026-04-08T12:00:00Z"
  }
}
```

---

### WS /ws/chat/:id

WebSocket 即時通訊。

**連線**: `wss://api.carebridge.app/v1/ws/chat/{chat_id}?token={access_token}`

**Client → Server（發送訊息）**:
```json
{
  "event": "message",
  "data": {
    "type": "text",
    "text": "Sudah minum obat"
  }
}
```

**Server → Client（接收訊息，已翻譯）**:
```json
{
  "event": "message",
  "data": {
    "id": "msg_004",
    "sender_id": "usr_abc123",
    "type": "text",
    "content": {
      "text": "Sudah minum obat",
      "translated": {
        "zh-TW": "已經吃藥了"
      }
    },
    "sent_at": "2026-04-08T14:00:00Z"
  }
}
```

**Server → Client（對方正在輸入）**:
```json
{
  "event": "typing",
  "data": {
    "user_id": "usr_def456",
    "is_typing": true
  }
}
```

---

## 4. Translation 翻譯

### POST /translate

文字翻譯。

**Request Body**:
```json
{
  "text": "請幫爸爸量血壓",
  "source_lang": "zh-TW",
  "target_lang": "id"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "original_text": "請幫爸爸量血壓",
    "translated_text": "Tolong ukur tekanan darah ayah",
    "source_lang": "zh-TW",
    "target_lang": "id"
  }
}
```

---

### POST /translate/speech

語音轉文字並翻譯。

**Request（multipart/form-data）**:
| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| audio | file | ✅ | 音訊檔案（m4a/wav） |
| source_lang | string | ✅ | 語音語言 |
| target_lang | string | ✅ | 目標翻譯語言 |

**Response 200**:
```json
{
  "success": true,
  "data": {
    "transcription": "Bapak sudah makan",
    "translated_text": "爸爸已經吃過了",
    "source_lang": "id",
    "target_lang": "zh-TW",
    "confidence": 0.94
  }
}
```

---

## 5. Board 留言板

### GET /boards/requests

取得採購需求列表。

**Query Parameters**: `?family_id=fam_xyz789&status=pending`

| 參數 | 說明 |
|---|---|
| status | `pending` / `approved` / `rejected` / `completed` |

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "req_001",
      "requester_id": "usr_abc123",
      "requester_name": "Siti Nurhaliza",
      "category": "food",
      "items": [
        { "name": "牛奶", "name_translated": "Susu", "quantity": "2 瓶" },
        { "name": "雞蛋", "name_translated": "Telur", "quantity": "1 盒" }
      ],
      "note": "Untuk sarapan besok",
      "note_translated": "明天早餐用",
      "status": "pending",
      "created_at": "2026-04-08T09:00:00Z"
    }
  ]
}
```

---

### POST /boards/requests

新增採購需求。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "category": "food",
  "items": [
    { "name": "Susu", "quantity": "2 botol" },
    { "name": "Telur", "quantity": "1 kotak" }
  ],
  "note": "Untuk sarapan besok"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| family_id | string | ✅ | 家庭 ID |
| category | enum | ✅ | `food` / `daily` / `medical` / `other` |
| items | array | ✅ | 需求品項 |
| note | string | ⬜ | 備註 |

**Response 201**: 同 GET 回應中的單筆格式，系統自動翻譯品項名稱。

---

### PUT /boards/requests/:id

確認或駁回需求。

**Request Body**:
```json
{
  "status": "approved",
  "reply": "好的，下班回來會買"
}
```

**Response 200**: 更新後的 request 物件。

---

## 6. Expense 消費紀錄

### POST /expenses/scan

上傳收據進行 OCR 解析。非同步處理，回傳 202 後由推播通知結果。

**Request（multipart/form-data）**:
| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| image | file | ✅ | 收據照片 |
| family_id | string | ✅ | 家庭 ID |

**Response 202**:
```json
{
  "success": true,
  "data": {
    "scan_id": "scan_001",
    "status": "processing",
    "message": "收據處理中，完成後將推播通知"
  }
}
```

**推播通知完成後，前端 GET /expenses/:id 取得結果**:
```json
{
  "success": true,
  "data": {
    "id": "exp_001",
    "scan_id": "scan_001",
    "family_id": "fam_xyz789",
    "recorder_id": "usr_abc123",
    "image_url": "https://storage.carebridge.app/receipts/scan_001.jpg",
    "store_name": "全聯福利中心",
    "date": "2026-04-08",
    "items": [
      { "name": "林鳳營鮮乳", "quantity": 2, "unit_price": 75, "total": 150, "category": "food" },
      { "name": "大成雞蛋", "quantity": 1, "unit_price": 69, "total": 69, "category": "food" },
      { "name": "舒潔衛生紙", "quantity": 1, "unit_price": 189, "total": 189, "category": "daily" }
    ],
    "total_amount": 408,
    "ocr_confidence": 0.96,
    "status": "completed",
    "created_at": "2026-04-08T11:00:00Z"
  }
}
```

---

### GET /expenses

消費紀錄列表。

**Query Parameters**: `?family_id=fam_xyz789&from=2026-04-01&to=2026-04-30&category=food`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "exp_001",
      "store_name": "全聯福利中心",
      "date": "2026-04-08",
      "total_amount": 408,
      "item_count": 3,
      "category_summary": { "food": 219, "daily": 189 },
      "recorder_name": "Siti Nurhaliza"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 12 }
}
```

---

### GET /expenses/monthly

月結帳單。

**Query Parameters**: `?family_id=fam_xyz789&year=2026&month=4`

**Response 200**:
```json
{
  "success": true,
  "data": {
    "year": 2026,
    "month": 4,
    "total_amount": 5230,
    "transaction_count": 12,
    "category_breakdown": [
      { "category": "food", "amount": 3200, "percentage": 61.2 },
      { "category": "daily", "amount": 1500, "percentage": 28.7 },
      { "category": "medical", "amount": 530, "percentage": 10.1 }
    ],
    "daily_trend": [
      { "date": "2026-04-01", "amount": 350 },
      { "date": "2026-04-03", "amount": 520 }
    ],
    "top_stores": [
      { "store_name": "全聯福利中心", "amount": 2800, "visit_count": 6 }
    ]
  }
}
```

---

### PUT /expenses/:id

修正 OCR 辨識結果。

**Request Body**:
```json
{
  "items": [
    { "name": "林鳳營鮮乳", "quantity": 2, "unit_price": 75, "total": 150, "category": "food" }
  ],
  "total_amount": 408
}
```

**Response 200**: 更新後的 expense 物件。

---

## 7. Leave 請假管理

### POST /leaves

申請請假。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "start_date": "2026-04-15",
  "end_date": "2026-04-16",
  "reason": "Pulang kampung",
  "type": "personal"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| family_id | string | ✅ | 家庭 ID |
| start_date | string | ✅ | 開始日期 |
| end_date | string | ✅ | 結束日期 |
| reason | string | ✅ | 請假原因（自動翻譯） |
| type | enum | ✅ | `personal` / `sick` / `emergency` |

**Response 201**:
```json
{
  "success": true,
  "data": {
    "id": "leave_001",
    "applicant_id": "usr_abc123",
    "applicant_name": "Siti Nurhaliza",
    "start_date": "2026-04-15",
    "end_date": "2026-04-16",
    "days": 2,
    "reason": "Pulang kampung",
    "reason_translated": "回鄉",
    "type": "personal",
    "status": "pending",
    "created_at": "2026-04-08T08:00:00Z"
  }
}
```

---

### GET /leaves

請假紀錄列表。

**Query Parameters**: `?family_id=fam_xyz789&status=pending&year=2026`

**Response 200**: 陣列，格式同上。

---

### PUT /leaves/:id

核准或駁回請假。

**Request Body**:
```json
{
  "status": "approved",
  "reply": "已核准，請安排交接事項"
}
```

**Response 200**: 更新後的 leave 物件，包含 `approved_by` 和 `approved_at` 欄位。

---

## 8. Care Log 照護日誌

### GET /care-logs

以時間軸格式取得照護紀錄。

**Query Parameters**: `?family_id=fam_xyz789&from=2026-04-01&to=2026-04-08&type=medication,vital`

| 參數 | 說明 |
|---|---|
| type | `medication` / `vital` / `meal` / `activity` / `mood` / `note`（可多選逗號分隔） |

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "log_001",
      "family_id": "fam_xyz789",
      "type": "medication",
      "recorder_id": "usr_abc123",
      "recorder_name": "Siti Nurhaliza",
      "timestamp": "2026-04-08T08:00:00Z",
      "content": {
        "medication_name": "降血壓藥 Amlodipine 5mg",
        "dosage": "1 顆",
        "status": "taken",
        "photo_url": "https://storage.carebridge.app/care-logs/log_001.jpg",
        "confirmed_by": "usr_def456",
        "confirmed_at": "2026-04-08T08:15:00Z"
      }
    },
    {
      "id": "log_002",
      "family_id": "fam_xyz789",
      "type": "vital",
      "recorder_id": "usr_abc123",
      "recorder_name": "Siti Nurhaliza",
      "timestamp": "2026-04-08T08:30:00Z",
      "content": {
        "blood_pressure_systolic": 128,
        "blood_pressure_diastolic": 82,
        "blood_sugar": null,
        "temperature": 36.5,
        "note": "Kondisi stabil"
      }
    },
    {
      "id": "log_003",
      "family_id": "fam_xyz789",
      "type": "meal",
      "recorder_id": "usr_abc123",
      "recorder_name": "Siti Nurhaliza",
      "timestamp": "2026-04-08T07:30:00Z",
      "content": {
        "meal_type": "breakfast",
        "description": "Bubur dengan ayam",
        "description_translated": "雞肉粥",
        "photo_url": null,
        "appetite": "good"
      }
    }
  ]
}
```

---

### POST /care-logs

新增照護紀錄。

**Request Body（用藥紀錄，multipart/form-data）**:
| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| family_id | string | ✅ | 家庭 ID |
| type | string | ✅ | 紀錄類型 |
| timestamp | string | ✅ | 紀錄時間 |
| content | json | ✅ | 紀錄內容（依 type 不同） |
| photo | file | ⬜ | 照片附件 |

**Response 201**: 新建的 care-log 物件。

---

### PUT /care-logs/:id

更新照護紀錄。

**Request Body**: 部分更新（僅傳需修改的欄位）。

**Response 200**: 更新後的物件。

---

### GET /care-logs/summary

取得照護摘要（供 AI Agent 使用）。

**Query Parameters**: `?family_id=fam_xyz789&days=7`

**Response 200**:
```json
{
  "success": true,
  "data": {
    "period": "2026-04-01 ~ 2026-04-08",
    "medication_compliance": 0.95,
    "vital_averages": {
      "blood_pressure_systolic": 130,
      "blood_pressure_diastolic": 84,
      "heart_rate": 72,
      "blood_oxygen": 97.2
    },
    "vital_alerts_count": 1,
    "meal_summary": { "good": 18, "fair": 3, "poor": 0 },
    "activity_count": 12,
    "mood_trend": "stable",
    "total_records": 45
  }
}
```

---

## 9. Medication 用藥管理

### GET /medications

藥物列表。

**Query Parameters**: `?family_id=fam_xyz789&active=true`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "med_001",
      "name": "Amlodipine 5mg",
      "name_translated": { "id": "Amlodipine 5mg", "zh-TW": "降血壓藥 脈優 5mg" },
      "dosage": "1 顆",
      "frequency": "daily",
      "times": ["08:00", "20:00"],
      "instructions": "飯後服用",
      "instructions_translated": { "id": "Diminum setelah makan" },
      "start_date": "2026-01-15",
      "end_date": null,
      "active": true,
      "reminder_enabled": true
    }
  ]
}
```

---

### POST /medications

新增藥物。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "name": "Amlodipine 5mg",
  "dosage": "1 顆",
  "frequency": "daily",
  "times": ["08:00", "20:00"],
  "instructions": "飯後服用",
  "start_date": "2026-01-15",
  "reminder_enabled": true
}
```

**Response 201**: 新建的 medication 物件。

---

### PUT /medications/:id

更新藥物資訊。

**Response 200**: 更新後的物件。

---

### POST /medications/:id/confirm

餵藥拍照確認。

**Request（multipart/form-data）**:
| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| photo | file | ✅ | 餵藥照片 |
| scheduled_time | string | ✅ | 排定服藥時間 |
| note | string | ⬜ | 備註 |

**Response 201**:
```json
{
  "success": true,
  "data": {
    "medication_id": "med_001",
    "confirmed_by": "usr_abc123",
    "photo_url": "https://storage.carebridge.app/medications/confirm_001.jpg",
    "scheduled_time": "08:00",
    "confirmed_at": "2026-04-08T08:05:00Z",
    "care_log_id": "log_auto_001"
  }
}
```

> 系統自動在照護日誌中建立一筆 `medication` 類型的紀錄。

---

## 10. Health 健康數據

### POST /health/sync

Apple Watch 健康數據批次同步。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "device_id": "watch_001",
  "data_points": [
    {
      "type": "heart_rate",
      "value": 72,
      "unit": "bpm",
      "recorded_at": "2026-04-08T10:00:00Z"
    },
    {
      "type": "blood_oxygen",
      "value": 97,
      "unit": "%",
      "recorded_at": "2026-04-08T10:00:00Z"
    },
    {
      "type": "heart_rate",
      "value": 118,
      "unit": "bpm",
      "recorded_at": "2026-04-08T10:05:00Z"
    }
  ]
}
```

| type 支援值 | 單位 | 說明 |
|---|---|---|
| `heart_rate` | bpm | 心率 |
| `blood_oxygen` | % | 血氧飽和度 |
| `step_count` | steps | 步數 |
| `active_energy` | kcal | 活動消耗熱量 |

**Response 200**:
```json
{
  "success": true,
  "data": {
    "synced_count": 3,
    "duplicates_skipped": 0,
    "alerts_triggered": [
      {
        "type": "heart_rate",
        "value": 118,
        "threshold": 100,
        "severity": "warning",
        "recorded_at": "2026-04-08T10:05:00Z"
      }
    ]
  }
}
```

> 如有異常，系統自動推播通知所有家庭成員。

---

### GET /health/data

歷史健康數據查詢。

**Query Parameters**: `?family_id=fam_xyz789&type=heart_rate&from=2026-04-07&to=2026-04-08&interval=hourly`

| 參數 | 說明 |
|---|---|
| interval | `raw`（原始）/ `hourly`（每小時平均）/ `daily`（每日平均） |

**Response 200**:
```json
{
  "success": true,
  "data": {
    "type": "heart_rate",
    "unit": "bpm",
    "interval": "hourly",
    "points": [
      { "timestamp": "2026-04-08T00:00:00Z", "avg": 62, "min": 58, "max": 68 },
      { "timestamp": "2026-04-08T01:00:00Z", "avg": 60, "min": 56, "max": 65 }
    ]
  }
}
```

---

### GET /health/dashboard

儀表板彙總數據。

**Query Parameters**: `?family_id=fam_xyz789`

**Response 200**:
```json
{
  "success": true,
  "data": {
    "current": {
      "heart_rate": { "value": 72, "status": "normal", "recorded_at": "2026-04-08T14:00:00Z" },
      "blood_oxygen": { "value": 97, "status": "normal", "recorded_at": "2026-04-08T14:00:00Z" }
    },
    "today_summary": {
      "heart_rate": { "avg": 70, "min": 58, "max": 118, "alerts": 1 },
      "blood_oxygen": { "avg": 97.2, "min": 95, "max": 99, "alerts": 0 },
      "steps": 3240,
      "active_energy": 180
    },
    "week_trend": {
      "heart_rate": [
        { "date": "2026-04-02", "avg": 71 },
        { "date": "2026-04-03", "avg": 69 }
      ]
    },
    "alert_thresholds": {
      "heart_rate": { "high": 100, "low": 50 },
      "blood_oxygen": { "low": 93 }
    }
  }
}
```

---

### GET /health/alerts

異常警示紀錄。

**Query Parameters**: `?family_id=fam_xyz789&from=2026-04-01&severity=warning,critical`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "alert_001",
      "type": "heart_rate",
      "value": 118,
      "threshold": 100,
      "severity": "warning",
      "recorded_at": "2026-04-08T10:05:00Z",
      "notified_members": ["usr_def456", "usr_ghi789"],
      "acknowledged_by": "usr_def456",
      "acknowledged_at": "2026-04-08T10:08:00Z"
    }
  ]
}
```

---

## 11. Calendar 行事曆 + 代辦事項

### GET /events

行程列表。

**Query Parameters**: `?family_id=fam_xyz789&from=2026-04-08&to=2026-04-14`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "evt_001",
      "family_id": "fam_xyz789",
      "title": "回診 - 心臟內科",
      "title_translated": { "id": "Kontrol - Kardiologi" },
      "start_time": "2026-04-10T09:00:00Z",
      "end_time": "2026-04-10T10:00:00Z",
      "location": "台大醫院",
      "reminder_minutes": 60,
      "type": "medical",
      "created_by": "usr_def456"
    }
  ]
}
```

---

### POST /events

新增行程。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "title": "回診 - 心臟內科",
  "start_time": "2026-04-10T09:00:00Z",
  "end_time": "2026-04-10T10:00:00Z",
  "location": "台大醫院",
  "reminder_minutes": 60,
  "type": "medical",
  "note": "記得帶健保卡"
}
```

| type 可選值 | 說明 |
|---|---|
| `medical` | 回診/就醫 |
| `medication` | 用藥提醒（自動由 Medication 建立） |
| `rehab` | 復健 |
| `personal` | 個人行程 |
| `other` | 其他 |

**Response 201**: 新建的 event 物件。

---

### PUT /events/:id

更新行程。

**Response 200**: 更新後的物件。

---

### DELETE /events/:id

刪除行程。

**Response 204**: No Content。

---

### GET /todos

代辦事項列表。

**Query Parameters**: `?family_id=fam_xyz789&status=pending&assignee=usr_abc123`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "todo_001",
      "family_id": "fam_xyz789",
      "title": "幫爸爸剪指甲",
      "title_translated": { "id": "Potong kuku ayah" },
      "assignee_id": "usr_abc123",
      "assignee_name": "Siti Nurhaliza",
      "priority": "medium",
      "status": "pending",
      "due_date": "2026-04-09",
      "created_by": "usr_def456",
      "created_at": "2026-04-08T08:00:00Z"
    }
  ]
}
```

---

### POST /todos

新增代辦事項。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "title": "幫爸爸剪指甲",
  "assignee_id": "usr_abc123",
  "priority": "medium",
  "due_date": "2026-04-09"
}
```

**Response 201**: 新建的 todo 物件。

---

### PUT /todos/:id

更新/完成代辦事項。

**Request Body**:
```json
{
  "status": "completed",
  "completed_at": "2026-04-09T15:00:00Z"
}
```

> 完成時自動在照護日誌中建立一筆 `activity` 類型紀錄。

**Response 200**: 更新後的物件。

---

## 12. Document 文件管理

### GET /documents

文件列表。

**Query Parameters**: `?family_id=fam_xyz789&category=insurance`

| category 可選值 | 說明 |
|---|---|
| `insurance` | 保險文件 |
| `medical` | 醫療文件 |
| `id_document` | 證件 |
| `contract` | 合約 |
| `other` | 其他 |

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "doc_001",
      "family_id": "fam_xyz789",
      "title": "國泰人壽保單",
      "category": "insurance",
      "file_url": "https://storage.carebridge.app/documents/doc_001.pdf",
      "file_size": 2048576,
      "mime_type": "application/pdf",
      "uploaded_by": "usr_def456",
      "uploaded_at": "2026-03-15T10:00:00Z"
    }
  ]
}
```

---

### POST /documents

上傳文件（multipart/form-data）。

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| file | file | ✅ | 文件檔案（PDF/JPG/PNG，上限 10MB） |
| family_id | string | ✅ | 家庭 ID |
| title | string | ✅ | 文件標題 |
| category | string | ✅ | 分類 |

**Response 201**: 新建的 document 物件。

---

### GET /documents/:id

取得文件下載連結。

**Response 200**:
```json
{
  "success": true,
  "data": {
    "id": "doc_001",
    "download_url": "https://storage.carebridge.app/documents/doc_001.pdf?token=temp_xxx",
    "expires_in": 3600
  }
}
```

---

### DELETE /documents/:id

刪除文件。

**Response 204**: No Content。

---

## 13. AI 智慧助理

### POST /ai/chat

對話式查詢 APP 內資訊。支援 SSE（Server-Sent Events）串流回應。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "message": "爸爸這週的血壓狀況如何？",
  "conversation_id": "conv_001"
}
```

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| family_id | string | ✅ | 家庭 ID |
| message | string | ✅ | 使用者訊息 |
| conversation_id | string | ⬜ | 多輪對話 ID（首次不填） |

**Response 200（SSE 串流）**:
```
Content-Type: text/event-stream

event: start
data: {"conversation_id": "conv_001"}

event: delta
data: {"text": "根據本週的照護紀錄，"}

event: delta
data: {"text": "爸爸的收縮壓平均為 130 mmHg，"}

event: delta
data: {"text": "舒張壓平均為 84 mmHg，整體趨勢穩定。"}

event: tool_call
data: {"tool": "query_health_data", "params": {"type": "blood_pressure", "days": 7}}

event: delta
data: {"text": "\n\n4月5日有一次收縮壓偏高（148 mmHg），建議留意是否與飲食或情緒有關。"}

event: done
data: {"conversation_id": "conv_001", "tokens_used": 320}
```

> **個資保護**：AI 不會回傳其他家庭成員的個人聯絡資訊、密碼等敏感資料。僅回傳照護相關資訊。

---

### POST /ai/handover-report

生成看護交接報告。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "period_days": 14,
  "target_language": "id"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "report_id": "rpt_001",
    "title": "看護交接報告 2026/03/25 - 2026/04/08",
    "content": {
      "zh-TW": "## 基本狀況概述\n王大明先生，80歲，主要診斷為高血壓...\n\n## 用藥紀錄\n- Amlodipine 5mg：每日兩次，服藥順從度 95%...\n\n## 生理數值趨勢\n- 平均血壓：130/84 mmHg...\n\n## 注意事項\n1. 4月5日血壓偏高，需持續觀察...",
      "id": "## Ringkasan Kondisi Umum\nBapak Wang Da Ming, 80 tahun, diagnosis utama hipertensi..."
    },
    "generated_at": "2026-04-08T15:00:00Z",
    "pdf_url": "https://storage.carebridge.app/reports/rpt_001.pdf"
  }
}
```

---

### POST /ai/care-analysis

近期照護記錄分析。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "period_days": 30,
  "focus_areas": ["vital_trends", "medication_compliance", "activity_level"]
}
```

| focus_areas 可選值 | 說明 |
|---|---|
| `vital_trends` | 生理數值趨勢分析 |
| `medication_compliance` | 用藥順從度分析 |
| `activity_level` | 活動量分析 |
| `meal_nutrition` | 飲食營養分析 |
| `mood_tracking` | 情緒趨勢 |
| `overall` | 綜合分析（預設） |

**Response 200**:
```json
{
  "success": true,
  "data": {
    "analysis_id": "ana_001",
    "period": "2026-03-09 ~ 2026-04-08",
    "summary": "整體照護狀況良好，血壓控制穩定，用藥順從度達 95%。建議增加每日步行量...",
    "sections": [
      {
        "area": "vital_trends",
        "title": "生理數值趨勢",
        "findings": "血壓平均 130/84，心率平均 72 bpm，血氧平均 97.2%。4月5日有單次血壓偏高。",
        "recommendations": ["持續監測血壓", "偏高時記錄當時活動與飲食"]
      },
      {
        "area": "medication_compliance",
        "title": "用藥順從度",
        "findings": "30天內應服 60 次，實際確認 57 次，順從度 95%。",
        "recommendations": ["維持目前良好的服藥習慣"]
      }
    ],
    "generated_at": "2026-04-08T15:30:00Z"
  }
}
```

---

### POST /ai/subsidy-form

政府補助表單自動生成。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "form_type": "long_term_care",
  "applicant_data": {
    "name": "王大明",
    "id_number": "A123456789",
    "birth_date": "1945-03-15",
    "address": "台北市大安區...",
    "care_level": 4,
    "disability_card": true
  }
}
```

| form_type 可選值 | 說明 |
|---|---|
| `long_term_care` | 長照服務補助 |
| `disability_allowance` | 身心障礙生活補助 |
| `foreign_caregiver` | 外籍看護工申請 |

**Response 200**:
```json
{
  "success": true,
  "data": {
    "form_id": "form_001",
    "form_type": "long_term_care",
    "filled_fields": {
      "applicant_name": "王大明",
      "id_number": "A123456789",
      "care_level": "第四級",
      "monthly_income": null,
      "required_documents": ["身分證影本", "診斷證明書", "身心障礙證明"]
    },
    "missing_fields": ["monthly_income", "bank_account"],
    "pdf_url": "https://storage.carebridge.app/forms/form_001.pdf",
    "instructions": "請補充月收入與銀行帳戶資訊後，攜帶所列文件至區公所長照管理中心申請。",
    "generated_at": "2026-04-08T16:00:00Z"
  }
}
```

---

### POST /ai/first-aid

AI 急救小幫手（RAG）。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "query": "Bapak tiba-tiba pingsan, apa yang harus saya lakukan?",
  "language": "id",
  "elder_conditions": ["hypertension", "diabetes"]
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "response": {
      "id": "Langkah-langkah darurat:\n1. Pastikan bapak berbaring di tempat aman...\n2. Periksa napas dan denyut nadi...\n3. Hubungi 119 segera...",
      "zh-TW": "緊急處理步驟：\n1. 確保長者躺在安全處...\n2. 檢查呼吸與脈搏...\n3. 立即撥打 119..."
    },
    "sources": [
      { "title": "衛福部急救手冊 - 昏厥處理", "section": "第三章第二節" },
      { "title": "高血壓患者急救注意事項", "source": "台灣心臟學會" }
    ],
    "disclaimer": "此資訊僅供參考，請立即撥打 119 或送醫。",
    "show_sos_button": true
  }
}
```

> **安全機制**：回應內容嚴格限制於衛福部認證的醫療資料範圍，附帶資料來源與免責聲明。回應中包含 `show_sos_button` 提示前端顯示 SOS 按鈕。

---

## 14. SOS 緊急呼叫

### POST /sos/trigger

觸發 SOS 緊急呼叫。

**Request Body**:
```json
{
  "family_id": "fam_xyz789",
  "trigger_by": "usr_abc123",
  "location": {
    "latitude": 25.0330,
    "longitude": 121.5654,
    "accuracy": 10.0,
    "address": "台北市大安區信義路四段..."
  },
  "situation": "Elder fell down",
  "auto_call_119": true
}
```

**Response 201**:
```json
{
  "success": true,
  "data": {
    "sos_id": "sos_001",
    "status": "triggered",
    "notified_members": [
      { "id": "usr_def456", "name": "王小華", "notified_at": "2026-04-08T14:00:01Z" },
      { "id": "usr_ghi789", "name": "王小明", "notified_at": "2026-04-08T14:00:01Z" }
    ],
    "call_119": true,
    "location": {
      "latitude": 25.0330,
      "longitude": 121.5654,
      "address": "台北市大安區信義路四段..."
    },
    "triggered_at": "2026-04-08T14:00:00Z"
  }
}
```

> 系統自動透過 APNs 推播通知所有家庭成員，通知內容包含 GPS 定位連結。

---

### GET /sos/history

SOS 歷史紀錄。

**Query Parameters**: `?family_id=fam_xyz789`

**Response 200**: SOS 紀錄陣列。

---

## 15. Notification 通知

### POST /notifications/device

註冊裝置推播 Token。

**Request Body**:
```json
{
  "device_token": "apns_token_xxx",
  "platform": "ios",
  "device_name": "iPhone 15 Pro"
}
```

**Response 200**:
```json
{
  "success": true,
  "data": {
    "device_id": "dev_001",
    "registered_at": "2026-04-08T08:00:00Z"
  }
}
```

---

### GET /notifications

通知列表。

**Query Parameters**: `?unread_only=true&page=1&limit=20`

**Response 200**:
```json
{
  "success": true,
  "data": [
    {
      "id": "notif_001",
      "type": "health_alert",
      "title": "心率異常警示",
      "title_translated": { "id": "Peringatan detak jantung abnormal" },
      "body": "長者心率達到 118 bpm，超過警戒值 100 bpm",
      "body_translated": { "id": "Detak jantung lansia mencapai 118 bpm, melebihi batas 100 bpm" },
      "data": {
        "alert_id": "alert_001",
        "action": "open_health_dashboard"
      },
      "read": false,
      "created_at": "2026-04-08T10:05:00Z"
    },
    {
      "id": "notif_002",
      "type": "leave_request",
      "title": "請假申請",
      "body": "看護 Siti 申請 4/15-4/16 請假",
      "data": {
        "leave_id": "leave_001",
        "action": "open_leave_detail"
      },
      "read": true,
      "created_at": "2026-04-08T08:00:00Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 5, "unread_count": 2 }
}
```

### 通知類型一覽

| type | 說明 | 觸發時機 |
|---|---|---|
| `health_alert` | 健康異常警示 | Watch 數據超出閾值 |
| `medication_reminder` | 用藥提醒 | 到達排定服藥時間 |
| `medication_confirmed` | 餵藥確認 | 看護確認已餵藥 |
| `leave_request` | 請假申請 | 看護提出請假 |
| `leave_approved` | 請假核准 | 家屬核准請假 |
| `leave_rejected` | 請假駁回 | 家屬駁回請假 |
| `board_request` | 採購需求 | 看護發送需求 |
| `board_approved` | 需求確認 | 家屬確認需求 |
| `expense_scanned` | 收據掃描完成 | OCR 處理完畢 |
| `sos_triggered` | SOS 緊急呼叫 | 觸發 SOS |
| `event_reminder` | 行程提醒 | 行程前 N 分鐘 |
| `chat_message` | 新訊息 | 收到聊天訊息 |

---

### PUT /notifications/:id/read

標記通知為已讀。

**Response 200**:
```json
{
  "success": true,
  "data": {
    "id": "notif_001",
    "read": true,
    "read_at": "2026-04-08T10:10:00Z"
  }
}
```

---

## 附錄：資料庫 Schema 概覽

### 主要資料表

| 資料表 | 說明 | 主要欄位 |
|---|---|---|
| `users` | 使用者 | id, email, name, role, language, family_id |
| `families` | 家庭群組 | id, name, elder_name, invite_code |
| `chats` | 聊天室 | id, type, family_id |
| `messages` | 聊天訊息 | id, chat_id, sender_id, type, content, translations |
| `board_requests` | 留言板需求 | id, family_id, requester_id, items, status |
| `expenses` | 消費紀錄 | id, family_id, items, total_amount, image_url |
| `leaves` | 請假紀錄 | id, family_id, applicant_id, dates, status |
| `care_logs` | 照護日誌 | id, family_id, type, content, timestamp |
| `medications` | 藥物管理 | id, family_id, name, dosage, times, active |
| `medication_confirmations` | 餵藥確認 | id, medication_id, photo_url, confirmed_at |
| `health_data` | 健康數據 | id, family_id, type, value, recorded_at |
| `health_alerts` | 健康警示 | id, family_id, type, value, severity |
| `events` | 行事曆 | id, family_id, title, start_time, type |
| `todos` | 代辦事項 | id, family_id, title, assignee_id, status |
| `documents` | 文件 | id, family_id, title, category, file_url |
| `notifications` | 通知 | id, user_id, type, title, body, read |
| `devices` | 裝置 Token | id, user_id, device_token, platform |
| `ai_conversations` | AI 對話 | id, family_id, messages_history |
| `sos_records` | SOS 紀錄 | id, family_id, location, status |

---

## 附錄：認證與權限

### 角色權限矩陣

| 功能 | caregiver | family_member (primary) | family_member | elder |
|---|---|---|---|---|
| 聊天/翻譯 | ✅ | ✅ | ✅ | ⬜ |
| 照護日誌（寫入） | ✅ | ✅ | ⬜ | ⬜ |
| 照護日誌（讀取） | ✅ | ✅ | ✅ | ⬜ |
| 用藥確認 | ✅ | ⬜ | ⬜ | ⬜ |
| 請假申請 | ✅ | ⬜ | ⬜ | ⬜ |
| 請假核准 | ⬜ | ✅ | ⬜ | ⬜ |
| 消費記帳 | ✅ | ✅ | ⬜ | ⬜ |
| 文件管理 | ⬜ | ✅ | ✅ | ⬜ |
| AI 智慧助理 | ✅ | ✅ | ✅ | ⬜ |
| SOS 觸發 | ✅ | ✅ | ✅ | ✅ |
| 健康數據 | ✅（讀） | ✅ | ✅（讀） | ⬜ |
| 留言板（需求） | ✅ | ⬜ | ⬜ | ⬜ |
| 留言板（確認） | ⬜ | ✅ | ✅ | ⬜ |

> `elder` 角色僅限 Apple Watch 被動資料收集與 SOS 功能。
