# CareBridge 照護橋 — API 文件

> **版本**: v2.0
> **最後更新**: 2026/04/12
> **Base URL**: `http://127.0.0.1:8000/api/v1`
> **認證方式**: JWT Bearer Token（SimpleJWT）
> **回應格式**: JSON

---

## 目錄

1. [通用說明](#通用說明)
2. [Auth 認證](#1-auth-認證)
3. [Family 家庭管理](#2-family-家庭管理)
4. [Chat 即時聊天](#3-chat-即時聊天)
5. [Board 留言板](#4-board-留言板)
6. [Care Log 照護日誌](#5-care-log-照護日誌)
7. [Medication 用藥管理](#6-medication-用藥管理)
8. [Expense 消費記帳](#7-expense-消費記帳)
9. [Leave 請假管理](#8-leave-請假管理)
10. [Health 健康監測](#9-health-健康監測)
11. [Calendar Event 行事曆](#10-calendar-event-行事曆)
12. [Todo 代辦事項](#11-todo-代辦事項)
13. [Document 文件管理](#12-document-文件管理)
14. [AI 智慧助理](#13-ai-智慧助理)
15. [SOS 緊急呼叫](#14-sos-緊急呼叫)
16. [Notification 通知系統](#15-notification-通知系統)
17. [附錄](#附錄)

---

## 通用說明

### 認證機制

所有需要認證的端點必須在 HTTP Header 中附帶 JWT Token：

```
Authorization: Bearer <access_token>
```

| 項目 | 說明 |
|---|---|
| Token 取得 | `POST /auth/token/`（登入取得 Token Pair） |
| Token 刷新 | `POST /auth/token/refresh/` |
| Access Token 有效期 | 1 小時 |
| Refresh Token 有效期 | 30 天 |
| Token 輪換 | 啟用（刷新時舊 Refresh Token 加入黑名單） |

### 統一回應格式

**成功回應：**

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 100
  }
}
```

**錯誤回應：**

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "欄位驗證失敗"
  }
}
```

### 分頁

列表端點支援分頁查詢參數：

| 參數 | 型別 | 預設值 | 說明 |
|---|---|---|---|
| `page` | Integer | 1 | 頁碼 |
| `page_size` | Integer | 20 | 每頁筆數（最大 100） |

### 錯誤代碼

| HTTP 狀態碼 | 代碼 | 說明 |
|---|---|---|
| 400 | `BAD_REQUEST` | 請求格式錯誤或缺少必要參數 |
| 401 | `UNAUTHORIZED` | 未提供 Token 或 Token 已過期 |
| 403 | `FORBIDDEN` | 無權限存取該資源 |
| 404 | `NOT_FOUND` | 資源不存在 |
| 422 | `VALIDATION_ERROR` | 欄位驗證失敗 |
| 500 | `INTERNAL_ERROR` | 伺服器內部錯誤 |

### 日期格式

所有日期時間欄位採用 ISO 8601 格式：

- 日期時間：`2026-04-12T08:30:00Z`
- 日期：`2026-04-12`

### 角色定義

| 角色代碼 | 說明 |
|---|---|
| `caregiver` | 看護（照護者） |
| `family_member` | 家屬 |
| `elder` | 長者 |

---

## 1. Auth 認證

### POST /auth/register/

註冊新使用者帳號。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123",
  "name": "王小美",
  "role": "caregiver",
  "language": "id",
  "phone": "0912345678"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "email": "caregiver@example.com",
      "name": "王小美",
      "role": "caregiver",
      "language": "id",
      "phone": "0912345678",
      "avatar_url": null,
      "family": null,
      "is_primary": false,
      "created_at": "2026-04-12T08:00:00Z"
    },
    "tokens": {
      "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
      "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6..."
    }
  }
}
```

---

### POST /auth/login/

使用者登入（自訂 SimpleJWT TokenObtainPairView）。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "email": "caregiver@example.com",
      "name": "王小美",
      "role": "caregiver",
      "language": "id",
      "family": {
        "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
        "name": "王家"
      }
    },
    "tokens": {
      "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
      "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6..."
    }
  }
}
```

---

### POST /auth/token/

取得 JWT Token Pair（SimpleJWT 標準端點）。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123"
}
```

**Response（200 OK）：**

```json
{
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6..."
}
```

---

### POST /auth/token/refresh/

刷新 Access Token（舊 Refresh Token 自動加入黑名單）。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6..."
}
```

**Response（200 OK）：**

```json
{
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6..."
}
```

---

### GET /auth/me/

取得目前登入使用者的個人資訊。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "email": "caregiver@example.com",
    "name": "王小美",
    "role": "caregiver",
    "language": "id",
    "phone": "0912345678",
    "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/a1b2c3d4.jpg",
    "family": {
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "王家",
      "elder_name": "王爺爺"
    },
    "is_primary": false,
    "created_at": "2026-04-12T08:00:00Z",
    "updated_at": "2026-04-12T10:30:00Z"
  }
}
```

---

### PUT /auth/me/

更新個人資訊（含頭像上傳至 S3）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Request Body（multipart/form-data 或 JSON）：**

```json
{
  "name": "王小美",
  "language": "zh-TW",
  "phone": "0987654321",
  "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/a1b2c3d4.jpg"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "email": "caregiver@example.com",
    "name": "王小美",
    "role": "caregiver",
    "language": "zh-TW",
    "phone": "0987654321",
    "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/a1b2c3d4.jpg",
    "family": {
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "王家"
    },
    "is_primary": false,
    "created_at": "2026-04-12T08:00:00Z",
    "updated_at": "2026-04-12T14:00:00Z"
  }
}
```

---

### POST /auth/forgot-password/

寄送密碼重設信（產生 15 分鐘有效期的重設 Token）。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "email": "caregiver@example.com"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "message": "密碼重設信已寄出"
  }
}
```

---

### POST /auth/reset-password/

使用重設 Token 重設密碼。

| 項目 | 說明 |
|---|---|
| 認證 | 否 |
| 權限 | 所有人 |

**Request Body：**

```json
{
  "token": "reset-token-string",
  "password": "newSecureP@ss456"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "message": "密碼已重設成功"
  }
}
```

---

### DELETE /auth/account/

刪除帳號（級聯刪除所有關聯資料）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（204 No Content）：**

無回應內容。

---

## 2. Family 家庭管理

### POST /families/

建立家庭群組（自動產生 8 位邀請碼，建立者自動加入為 primary family_member）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "name": "王家",
  "elder_name": "王大明",
  "elder_birth_date": "1945-03-15"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "王家",
    "elder_name": "王大明",
    "elder_birth_date": "1945-03-15",
    "invite_code": "A3F8B2D1",
    "created_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "members": [
      {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明",
        "role": "family_member",
        "is_primary": true
      }
    ],
    "created_at": "2026-04-12T08:00:00Z"
  }
}
```

---

### GET /families/:id/

取得家庭資訊與成員列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder（需為該家庭成員） |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "王家",
    "elder_name": "王大明",
    "elder_birth_date": "1945-03-15",
    "invite_code": "A3F8B2D1",
    "created_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "members": [
      {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明",
        "role": "family_member",
        "is_primary": true,
        "language": "zh-TW",
        "avatar_url": null
      },
      {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti",
        "role": "caregiver",
        "is_primary": false,
        "language": "id",
        "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/b2c3d4e5.jpg"
      }
    ],
    "created_at": "2026-04-12T08:00:00Z",
    "updated_at": "2026-04-12T09:00:00Z"
  }
}
```

---

### POST /families/:id/members/

透過邀請碼加入家庭。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Request Body：**

```json
{
  "invite_code": "A3F8B2D1"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "message": "已成功加入家庭",
    "family": {
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "王家"
    }
  }
}
```

---

### DELETE /families/:id/members/:userId/

移除家庭成員。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member（需為 primary） |

**Response（204 No Content）：**

無回應內容。

---

## 3. Chat 即時聊天

### GET /chats/

取得聊天室列表（含未讀計數）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "c1d2e3f4-a5b6-7890-cdef-123456789012",
      "type": "group",
      "name": "王家群組",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "members": [
        {
          "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "name": "王小明",
          "avatar_url": null
        },
        {
          "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
          "name": "Siti",
          "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/b2c3d4e5.jpg"
        }
      ],
      "last_message": {
        "content": "爺爺今天吃得不錯",
        "sender": "Siti",
        "sent_at": "2026-04-12T12:30:00Z"
      },
      "unread_count": 3,
      "created_at": "2026-04-10T08:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 2
  }
}
```

---

### POST /chats/

建立聊天室（group 或 direct）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Request Body：**

```json
{
  "type": "group",
  "name": "王家群組",
  "member_ids": [
    "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "b2c3d4e5-f6a7-8901-bcde-f12345678901"
  ]
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "c1d2e3f4-a5b6-7890-cdef-123456789012",
    "type": "group",
    "name": "王家群組",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "members": [
      {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      }
    ],
    "created_at": "2026-04-12T08:00:00Z"
  }
}
```

---

### GET /chats/:id/messages/

取得聊天訊息歷史（cursor-based 分頁）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder（需為聊天室成員） |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `cursor` | String | 分頁游標（上次回應的 `next_cursor`） |
| `page_size` | Integer | 每頁筆數（預設 20） |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "m1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "chat": "c1d2e3f4-a5b6-7890-cdef-123456789012",
      "sender": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti",
        "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/b2c3d4e5.jpg"
      },
      "type": "text",
      "content": "Kakek hari ini makan dengan baik",
      "translations": {
        "zh-TW": "爺爺今天吃得不錯",
        "id": "Kakek hari ini makan dengan baik"
      },
      "image_url": null,
      "sent_at": "2026-04-12T12:30:00Z"
    },
    {
      "id": "m2b3c4d5-e6f7-8901-bcde-f12345678902",
      "chat": "c1d2e3f4-a5b6-7890-cdef-123456789012",
      "sender": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti",
        "avatar_url": "https://carebridge-storage.s3.amazonaws.com/avatars/b2c3d4e5.jpg"
      },
      "type": "image",
      "content": null,
      "translations": null,
      "image_url": "https://carebridge-storage.s3.amazonaws.com/chat/m2b3c4d5.jpg",
      "sent_at": "2026-04-12T12:31:00Z"
    }
  ],
  "meta": {
    "next_cursor": "cD0yMDI2LTA0LTEyVDEyOjMwOjAwWg==",
    "has_next": true
  }
}
```

---

### POST /chats/:id/messages/

發送訊息（HTTP fallback，文字訊息自動觸發翻譯）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder（需為聊天室成員） |

**Request Body（文字訊息）：**

```json
{
  "type": "text",
  "content": "爺爺今天吃得不錯"
}
```

**Request Body（圖片訊息，multipart/form-data）：**

```json
{
  "type": "image",
  "image": "<binary file>"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "m3c4d5e6-f7a8-9012-cdef-123456789012",
    "chat": "c1d2e3f4-a5b6-7890-cdef-123456789012",
    "sender": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "type": "text",
    "content": "爺爺今天吃得不錯",
    "translations": {
      "zh-TW": "爺爺今天吃得不錯",
      "id": "Kakek hari ini makan dengan baik"
    },
    "image_url": null,
    "sent_at": "2026-04-12T13:00:00Z"
  }
}
```

---

### WebSocket: ws://host/ws/chat/:chatId/

即時聊天 WebSocket 連線（Django Channels）。

| 項目 | 說明 |
|---|---|
| 認證 | 是（Token 透過 query string `?token=<access_token>`） |
| 權限 | caregiver / family_member / elder（需為聊天室成員） |

**連線 URL：**

```
ws://127.0.0.1:8000/ws/chat/c1d2e3f4-a5b6-7890-cdef-123456789012/?token=eyJhbGci...
```

**發送訊息格式：**

```json
{
  "action": "message",
  "data": {
    "type": "text",
    "content": "你好"
  }
}
```

**接收訊息格式：**

```json
{
  "action": "message",
  "data": {
    "id": "m4d5e6f7-a8b9-0123-cdef-123456789012",
    "sender": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "type": "text",
    "content": "Halo",
    "translations": {
      "zh-TW": "你好",
      "id": "Halo"
    },
    "sent_at": "2026-04-12T13:05:00Z"
  }
}
```

**「正在輸入」狀態：**

```json
{
  "action": "typing",
  "data": {
    "user_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "is_typing": true
  }
}
```

---

## 4. Board 留言板

### GET /board/

取得採購需求列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `status` | String | 篩選狀態：`pending` / `approved` / `rejected` / `completed` |
| `category` | String | 篩選分類：`food` / `daily` / `medical` / `other` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "b1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "requester": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "category": "food",
      "items": [
        {
          "name": "Susu",
          "name_translated": "牛奶",
          "quantity": "2 盒"
        },
        {
          "name": "Roti",
          "name_translated": "麵包",
          "quantity": "1 條"
        }
      ],
      "note": "Untuk sarapan kakek",
      "note_translated": "給爺爺當早餐",
      "status": "pending",
      "reply": null,
      "reviewed_by": null,
      "created_at": "2026-04-12T07:00:00Z",
      "updated_at": "2026-04-12T07:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 5
  }
}
```

---

### POST /board/

建立採購需求（品項自動翻譯，推播通知家屬）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver |

**Request Body：**

```json
{
  "category": "food",
  "items": [
    {
      "name": "Susu",
      "quantity": "2 盒"
    },
    {
      "name": "Roti",
      "quantity": "1 條"
    }
  ],
  "note": "Untuk sarapan kakek"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "b1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "requester": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "category": "food",
    "items": [
      {
        "name": "Susu",
        "name_translated": "牛奶",
        "quantity": "2 盒"
      },
      {
        "name": "Roti",
        "name_translated": "麵包",
        "quantity": "1 條"
      }
    ],
    "note": "Untuk sarapan kakek",
    "note_translated": "給爺爺當早餐",
    "status": "pending",
    "created_at": "2026-04-12T07:00:00Z"
  }
}
```

---

### GET /board/:id/

取得單筆採購需求。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "b1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "requester": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "category": "food",
    "items": [
      {
        "name": "Susu",
        "name_translated": "牛奶",
        "quantity": "2 盒"
      }
    ],
    "note": "Untuk sarapan kakek",
    "note_translated": "給爺爺當早餐",
    "status": "pending",
    "reply": null,
    "reviewed_by": null,
    "created_at": "2026-04-12T07:00:00Z",
    "updated_at": "2026-04-12T07:00:00Z"
  }
}
```

---

### PUT /board/:id/

更新採購需求。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver（限建立者本人） |

**Request Body：**

```json
{
  "category": "food",
  "items": [
    {
      "name": "Susu",
      "quantity": "3 盒"
    }
  ],
  "note": "Tambah satu lagi"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "b1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "category": "food",
    "items": [
      {
        "name": "Susu",
        "name_translated": "牛奶",
        "quantity": "3 盒"
      }
    ],
    "note": "Tambah satu lagi",
    "note_translated": "再多加一個",
    "status": "pending",
    "updated_at": "2026-04-12T08:00:00Z"
  }
}
```

---

### PATCH /board/:id/status/

核准或駁回採購需求（推播通知看護）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "status": "approved",
  "reply": "好的，我下班會買回來"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "b1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "status": "approved",
    "reply": "好的，我下班會買回來",
    "reviewed_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "updated_at": "2026-04-12T09:00:00Z"
  }
}
```

---

## 5. Care Log 照護日誌

### GET /care-logs/

取得照護日誌時間軸列表（支援類型篩選、日期區間）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `type` | String | 篩選類型：`medication` / `vital` / `meal` / `activity` / `note` |
| `start_date` | Date | 起始日期（ISO 8601） |
| `end_date` | Date | 結束日期（ISO 8601） |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "cl1a2b3c-d4e5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "recorder": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "type": "medication",
      "content": {
        "medication_name": "Amlodipine 5mg",
        "dosage": "1 顆",
        "status": "taken",
        "confirmed_by": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "confirmed_at": "2026-04-12T08:15:00Z"
      },
      "photo_url": "https://carebridge-storage.s3.amazonaws.com/care-logs/cl1a2b3c.jpg",
      "timestamp": "2026-04-12T08:15:00Z",
      "created_at": "2026-04-12T08:15:00Z"
    },
    {
      "id": "cl2b3c4d-e5f6-7890-bcde-f12345678901",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "recorder": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "type": "meal",
      "content": {
        "meal_type": "breakfast",
        "description": "雞肉粥",
        "description_translated": "Bubur ayam",
        "appetite": "good"
      },
      "photo_url": null,
      "timestamp": "2026-04-12T07:30:00Z",
      "created_at": "2026-04-12T07:35:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 45
  }
}
```

---

### POST /care-logs/

新增照護日誌（支援 5 種類型，照片上傳至 S3，文字自動翻譯）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver |

**Request Body（type = vital）：**

```json
{
  "type": "vital",
  "content": {
    "blood_pressure_systolic": 128,
    "blood_pressure_diastolic": 82,
    "blood_sugar": 5.8,
    "temperature": 36.5,
    "note": "狀況穩定"
  },
  "timestamp": "2026-04-12T09:00:00Z",
  "photo_url": null
}
```

**Request Body（type = meal）：**

```json
{
  "type": "meal",
  "content": {
    "meal_type": "lunch",
    "description": "Nasi goreng",
    "appetite": "good"
  },
  "timestamp": "2026-04-12T12:00:00Z"
}
```

**Request Body（type = note）：**

```json
{
  "type": "note",
  "content": {
    "text": "Hari ini semangatnya baik"
  },
  "timestamp": "2026-04-12T14:00:00Z"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "cl3c4d5e-f6a7-8901-cdef-123456789012",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "recorder": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "type": "vital",
    "content": {
      "blood_pressure_systolic": 128,
      "blood_pressure_diastolic": 82,
      "blood_sugar": 5.8,
      "temperature": 36.5,
      "note": "狀況穩定"
    },
    "photo_url": null,
    "timestamp": "2026-04-12T09:00:00Z",
    "created_at": "2026-04-12T09:00:00Z"
  }
}
```

---

### PUT /care-logs/:id/

更新照護日誌紀錄。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver（限紀錄者本人） |

**Request Body：**

```json
{
  "content": {
    "blood_pressure_systolic": 130,
    "blood_pressure_diastolic": 85,
    "blood_sugar": 6.0,
    "temperature": 36.5,
    "note": "血壓微高，持續觀察"
  }
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "cl3c4d5e-f6a7-8901-cdef-123456789012",
    "type": "vital",
    "content": {
      "blood_pressure_systolic": 130,
      "blood_pressure_diastolic": 85,
      "blood_sugar": 6.0,
      "temperature": 36.5,
      "note": "血壓微高，持續觀察"
    },
    "timestamp": "2026-04-12T09:00:00Z",
    "created_at": "2026-04-12T09:00:00Z"
  }
}
```

---

### GET /care-logs/summary/

照護摘要（聚合統計：用藥順從度、生理平均值、飲食統計、活動統計）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `start_date` | Date | 起始日期 |
| `end_date` | Date | 結束日期 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "period": {
      "start_date": "2026-04-06",
      "end_date": "2026-04-12"
    },
    "medication_compliance": {
      "confirmed": 12,
      "total": 14,
      "rate": 0.857
    },
    "vitals_average": {
      "blood_pressure_systolic": 126.5,
      "blood_pressure_diastolic": 80.3,
      "blood_sugar": 5.9,
      "temperature": 36.4
    },
    "meals": {
      "total": 18,
      "appetite": {
        "good": 12,
        "fair": 5,
        "poor": 1
      }
    },
    "activities": {
      "total": 5,
      "total_duration_minutes": 150
    }
  }
}
```

---

## 6. Medication 用藥管理

### GET /medications/

取得藥物清單。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `is_active` | Boolean | 篩選啟用/停用藥物 |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "med1a2b3-c4d5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "Amlodipine 5mg",
      "name_translated": {
        "zh-TW": "脈優 5mg",
        "id": "Amlodipine 5mg"
      },
      "dosage": "1 顆",
      "frequency": "daily",
      "times": ["08:00", "20:00"],
      "instructions": "飯後服用",
      "instructions_translated": {
        "zh-TW": "飯後服用",
        "id": "Diminum setelah makan"
      },
      "start_date": "2026-01-01",
      "end_date": null,
      "is_active": true,
      "reminder_enabled": true,
      "created_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-01-01T08:00:00Z",
      "updated_at": "2026-04-01T10:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 3
  }
}
```

---

### POST /medications/

新增藥物（自動翻譯藥物名稱與說明，自動建立 calendar_event 用藥提醒）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "name": "Metformin 500mg",
  "dosage": "1 顆",
  "frequency": "twice_daily",
  "times": ["08:00", "20:00"],
  "instructions": "飯後服用，不可空腹",
  "start_date": "2026-04-12",
  "end_date": null,
  "reminder_enabled": true
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "med2b3c4-d5e6-7890-bcde-f12345678901",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "Metformin 500mg",
    "name_translated": {
      "zh-TW": "二甲雙胍 500mg",
      "id": "Metformin 500mg"
    },
    "dosage": "1 顆",
    "frequency": "twice_daily",
    "times": ["08:00", "20:00"],
    "instructions": "飯後服用，不可空腹",
    "instructions_translated": {
      "zh-TW": "飯後服用，不可空腹",
      "id": "Diminum setelah makan, jangan saat perut kosong"
    },
    "start_date": "2026-04-12",
    "end_date": null,
    "is_active": true,
    "reminder_enabled": true,
    "created_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "created_at": "2026-04-12T10:00:00Z",
    "updated_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### PUT /medications/:id/

更新藥物資訊。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "dosage": "2 顆",
  "times": ["08:00", "14:00", "20:00"],
  "frequency": "daily",
  "instructions": "飯後服用，一天三次"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "med2b3c4-d5e6-7890-bcde-f12345678901",
    "name": "Metformin 500mg",
    "dosage": "2 顆",
    "frequency": "daily",
    "times": ["08:00", "14:00", "20:00"],
    "instructions": "飯後服用，一天三次",
    "is_active": true,
    "updated_at": "2026-04-12T11:00:00Z"
  }
}
```

---

---

### GET /medications/today_confirmations/

取得當天家族內所有的用藥確認紀錄（服藥打勾狀態同步）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "mc1a2b3c-d4e5-6789-abcd-ef1234567890",
      "medication": "med1a2b3-c4d5-6789-abcd-ef1234567890",
      "confirmed_by": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "photo_url": null,
      "scheduled_time": "08:00",
      "note": "順利服藥",
      "confirmed_at": "2026-04-12T08:15:00Z"
    }
  ]
}
```

---

### POST /medications/:id/confirm/

餵藥確認（照片已設為選填參數，自動建立 care_log 用藥紀錄，推播通知家屬）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body（JSON）：**

```json
{
  "photo_url": null,
  "scheduled_time": "08:00",
  "note": "順利服藥"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "mc1a2b3c-d4e5-6789-abcd-ef1234567890",
    "medication": {
      "id": "med1a2b3-c4d5-6789-abcd-ef1234567890",
      "name": "Amlodipine 5mg"
    },
    "confirmed_by": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "photo_url": "https://carebridge-storage.s3.amazonaws.com/medications/mc1a2b3c.jpg",
    "scheduled_time": "08:00",
    "note": "順利服藥",
    "care_log": {
      "id": "cl4d5e6f-a7b8-9012-cdef-123456789012"
    },
    "confirmed_at": "2026-04-12T08:15:00Z"
  }
}
```

---

## 7. Expense 消費記帳

### GET /expenses/

取得消費紀錄列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `start_date` | Date | 起始日期 |
| `end_date` | Date | 結束日期 |
| `category` | String | 品項分類篩選（`food` / `daily` / `medical` / `other`） |
| `status` | String | 狀態：`processing` / `completed` / `failed` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "exp1a2b3-c4d5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "recorder": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "scan_id": null,
      "store_name": "全聯福利中心",
      "date": "2026-04-12",
      "items": [
        {
          "name": "鮮乳",
          "quantity": 2,
          "unit_price": 75,
          "total": 150,
          "category": "food"
        },
        {
          "name": "衛生紙",
          "quantity": 1,
          "unit_price": 189,
          "total": 189,
          "category": "daily"
        }
      ],
      "total_amount": "339.00",
      "image_url": null,
      "ocr_confidence": null,
      "status": "completed",
      "created_at": "2026-04-12T15:00:00Z",
      "updated_at": "2026-04-12T15:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 12
  }
}
```

---

### POST /expenses/scan/

收據 OCR 掃描（非同步處理：上傳照片 → Celery 背景任務 GPT-4o Vision 辨識 → 推播通知）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver |

**Request Body（multipart/form-data）：**

```json
{
  "image": "<binary receipt image>"
}
```

**Response（202 Accepted）：**

```json
{
  "success": true,
  "data": {
    "scan_id": "scan_20260412_001",
    "status": "processing",
    "message": "收據已上傳，正在辨識中"
  }
}
```

---

### GET /expenses/:id/

取得單筆消費紀錄。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "exp1a2b3-c4d5-6789-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "recorder": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "scan_id": "scan_20260412_001",
    "store_name": "全聯福利中心",
    "date": "2026-04-12",
    "items": [
      {
        "name": "鮮乳",
        "quantity": 2,
        "unit_price": 75,
        "total": 150,
        "category": "food"
      }
    ],
    "total_amount": "150.00",
    "image_url": "https://carebridge-storage.s3.amazonaws.com/receipts/scan_20260412_001.jpg",
    "ocr_confidence": 0.95,
    "status": "completed",
    "created_at": "2026-04-12T15:00:00Z",
    "updated_at": "2026-04-12T15:01:00Z"
  }
}
```

---

### PUT /expenses/:id/

修正消費紀錄（例如修正 OCR 辨識結果）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "store_name": "全聯福利中心 信義店",
  "date": "2026-04-12",
  "items": [
    {
      "name": "鮮乳",
      "quantity": 2,
      "unit_price": 75,
      "total": 150,
      "category": "food"
    }
  ],
  "total_amount": 150.00
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "exp1a2b3-c4d5-6789-abcd-ef1234567890",
    "store_name": "全聯福利中心 信義店",
    "date": "2026-04-12",
    "items": [
      {
        "name": "鮮乳",
        "quantity": 2,
        "unit_price": 75,
        "total": 150,
        "category": "food"
      }
    ],
    "total_amount": "150.00",
    "updated_at": "2026-04-12T16:00:00Z"
  }
}
```

---

### GET /expenses/monthly/

月結帳單（按分類/日期聚合統計）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `year` | Integer | 年份（例：2026） |
| `month` | Integer | 月份（例：4） |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "year": 2026,
    "month": 4,
    "total_amount": "12580.00",
    "total_count": 25,
    "by_category": [
      {
        "category": "food",
        "amount": "6800.00",
        "count": 15
      },
      {
        "category": "daily",
        "amount": "2300.00",
        "count": 5
      },
      {
        "category": "medical",
        "amount": "3480.00",
        "count": 5
      }
    ],
    "by_date": [
      {
        "date": "2026-04-01",
        "amount": "450.00",
        "count": 2
      },
      {
        "date": "2026-04-02",
        "amount": "680.00",
        "count": 3
      }
    ]
  }
}
```

---

## 8. Leave 請假管理

### GET /leaves/

取得請假紀錄列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `status` | String | 篩選狀態：`pending` / `approved` / `rejected` |
| `type` | String | 假別：`personal` / `sick` / `emergency` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "lv1a2b3c-d4e5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "applicant": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "type": "personal",
      "start_date": "2026-04-15",
      "end_date": "2026-04-16",
      "days": 2,
      "reason": "Pulang kampung",
      "reason_translated": "回鄉探親",
      "status": "pending",
      "reply": null,
      "reviewed_by": null,
      "reviewed_at": null,
      "calendar_event": null,
      "created_at": "2026-04-12T08:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 3
  }
}
```

---

### POST /leaves/

申請請假（原因自動翻譯，推播通知家屬）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver |

**Request Body：**

```json
{
  "type": "personal",
  "start_date": "2026-04-15",
  "end_date": "2026-04-16",
  "days": 2,
  "reason": "Pulang kampung untuk acara keluarga"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "lv1a2b3c-d4e5-6789-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "applicant": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "type": "personal",
    "start_date": "2026-04-15",
    "end_date": "2026-04-16",
    "days": 2,
    "reason": "Pulang kampung untuk acara keluarga",
    "reason_translated": "回鄉參加家庭活動",
    "status": "pending",
    "created_at": "2026-04-12T08:00:00Z"
  }
}
```

---

### PATCH /leaves/:id/status/

核准或駁回請假（核准時自動建立 calendar_event，推播通知看護）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "status": "approved",
  "reply": "已核准，請提前安排交接"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "lv1a2b3c-d4e5-6789-abcd-ef1234567890",
    "status": "approved",
    "reply": "已核准，請提前安排交接",
    "reviewed_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "reviewed_at": "2026-04-12T10:00:00Z",
    "calendar_event": {
      "id": "evt1a2b3-c4d5-6789-abcd-ef1234567890",
      "title": "看護請假：Siti",
      "start_time": "2026-04-15T00:00:00Z",
      "end_time": "2026-04-16T23:59:59Z"
    }
  }
}
```

---

## 9. Health 健康監測

### POST /health-data/sync/

批次同步 Apple Watch 健康數據（去重處理，即時異常檢測，超過閾值觸發警示）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / elder |

**Request Body：**

```json
{
  "device_id": "apple-watch-001",
  "records": [
    {
      "type": "heart_rate",
      "value": 72,
      "unit": "bpm",
      "recorded_at": "2026-04-12T10:00:00Z"
    },
    {
      "type": "heart_rate",
      "value": 75,
      "unit": "bpm",
      "recorded_at": "2026-04-12T10:05:00Z"
    },
    {
      "type": "blood_oxygen",
      "value": 98.5,
      "unit": "%",
      "recorded_at": "2026-04-12T10:00:00Z"
    },
    {
      "type": "step_count",
      "value": 320,
      "unit": "steps",
      "recorded_at": "2026-04-12T10:00:00Z"
    },
    {
      "type": "active_energy",
      "value": 45.2,
      "unit": "kcal",
      "recorded_at": "2026-04-12T10:00:00Z"
    }
  ]
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "synced": 5,
    "duplicates_skipped": 0,
    "alerts_triggered": 0
  }
}
```

---

### GET /health-data/

查詢健康數據（支援 raw / hourly / daily 聚合）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `type` | String | 資料類型：`heart_rate` / `blood_oxygen` / `step_count` / `active_energy` |
| `start_date` | DateTime | 起始時間（ISO 8601） |
| `end_date` | DateTime | 結束時間（ISO 8601） |
| `aggregation` | String | 聚合方式：`raw`（預設）/ `hourly` / `daily` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK，aggregation=raw）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "hd1a2b3c-d4e5-6789-abcd-ef1234567890",
      "type": "heart_rate",
      "value": "72.00",
      "unit": "bpm",
      "device_id": "apple-watch-001",
      "recorded_at": "2026-04-12T10:00:00Z"
    },
    {
      "id": "hd2b3c4d-e5f6-7890-bcde-f12345678901",
      "type": "heart_rate",
      "value": "75.00",
      "unit": "bpm",
      "device_id": "apple-watch-001",
      "recorded_at": "2026-04-12T10:05:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 288
  }
}
```

**Response（200 OK，aggregation=hourly）：**

```json
{
  "success": true,
  "data": [
    {
      "hour": "2026-04-12T10:00:00Z",
      "type": "heart_rate",
      "avg": 73.5,
      "min": 68.0,
      "max": 82.0,
      "count": 12
    },
    {
      "hour": "2026-04-12T11:00:00Z",
      "type": "heart_rate",
      "avg": 76.2,
      "min": 70.0,
      "max": 85.0,
      "count": 12
    }
  ]
}
```

---

### GET /health-data/dashboard/

健康儀表板彙總（最新數值 + 今日統計）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "latest": {
      "heart_rate": {
        "value": 75.0,
        "unit": "bpm",
        "recorded_at": "2026-04-12T14:30:00Z"
      },
      "blood_oxygen": {
        "value": 98.5,
        "unit": "%",
        "recorded_at": "2026-04-12T14:30:00Z"
      },
      "step_count": {
        "value": 3250,
        "unit": "steps",
        "recorded_at": "2026-04-12T14:30:00Z"
      },
      "active_energy": {
        "value": 185.5,
        "unit": "kcal",
        "recorded_at": "2026-04-12T14:30:00Z"
      }
    },
    "today_summary": {
      "heart_rate_avg": 74.2,
      "heart_rate_min": 58.0,
      "heart_rate_max": 92.0,
      "blood_oxygen_avg": 97.8,
      "total_steps": 3250,
      "total_active_energy": 185.5
    },
    "alerts_today": 0
  }
}
```

---

### GET /health-data/alerts/

健康異常警示紀錄。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `acknowledged` | Boolean | 篩選已確認/未確認 |
| `severity` | String | 嚴重度：`warning` / `critical` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "ha1a2b3c-d4e5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "type": "heart_rate",
      "value": "112.00",
      "threshold": "100.00",
      "severity": "warning",
      "acknowledged_by": null,
      "acknowledged_at": null,
      "recorded_at": "2026-04-12T11:30:00Z",
      "created_at": "2026-04-12T11:30:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 2
  }
}
```

---

### PUT /health-data/alerts/:id/acknowledge/

確認（acknowledge）健康警示。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "ha1a2b3c-d4e5-6789-abcd-ef1234567890",
    "acknowledged_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "acknowledged_at": "2026-04-12T12:00:00Z"
  }
}
```

---

### PUT /health-data/thresholds/

更新健康異常閾值設定。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "heart_rate_high": 110,
  "heart_rate_low": 45,
  "blood_oxygen_low": 92.0
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "ht1a2b3c-d4e5-6789-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "heart_rate_high": 110,
    "heart_rate_low": 45,
    "blood_oxygen_low": 92.0,
    "updated_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "updated_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### GET /health-data/weekly-steps/

每週步數統計。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `date` | Date | 指定週的任意日期（預設：本週） |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "week_start": "2026-04-06",
    "week_end": "2026-04-12",
    "total_steps": 28500,
    "daily": [
      { "date": "2026-04-06", "steps": 4200 },
      { "date": "2026-04-07", "steps": 3800 },
      { "date": "2026-04-08", "steps": 4500 },
      { "date": "2026-04-09", "steps": 3600 },
      { "date": "2026-04-10", "steps": 4100 },
      { "date": "2026-04-11", "steps": 5050 },
      { "date": "2026-04-12", "steps": 3250 }
    ]
  }
}
```

---

## 10. Calendar Event 行事曆

### GET /events/

取得行事曆事件列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `start_time` | DateTime | 起始時間 |
| `end_time` | DateTime | 結束時間 |
| `type` | String | 事件類型：`medical` / `medication` / `rehab` / `leave` / `personal` / `other` |
| `source` | String | 來源：`manual` / `medication` / `leave` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "evt1a2b3-c4d5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "title": "回診 - 台大心臟內科",
      "title_translated": {
        "zh-TW": "回診 - 台大心臟內科",
        "id": "Kontrol - Kardiologi NTU"
      },
      "start_time": "2026-04-15T09:00:00Z",
      "end_time": "2026-04-15T11:00:00Z",
      "location": "台大醫院",
      "type": "medical",
      "reminder_minutes": 60,
      "note": "記得帶健保卡和上次檢查報告",
      "source": "manual",
      "source_id": null,
      "created_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-04-10T08:00:00Z"
    },
    {
      "id": "evt2b3c4-d5e6-7890-bcde-f12345678901",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "title": "用藥提醒：Amlodipine 5mg",
      "title_translated": {
        "zh-TW": "用藥提醒：脈優 5mg",
        "id": "Pengingat obat: Amlodipine 5mg"
      },
      "start_time": "2026-04-12T08:00:00Z",
      "end_time": null,
      "location": null,
      "type": "medication",
      "reminder_minutes": 15,
      "note": null,
      "source": "medication",
      "source_id": "med1a2b3-c4d5-6789-abcd-ef1234567890",
      "created_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-01-01T08:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 15
  }
}
```

---

### POST /events/

建立行事曆事件（標題自動翻譯）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "title": "復健治療",
  "start_time": "2026-04-16T14:00:00Z",
  "end_time": "2026-04-16T15:00:00Z",
  "location": "陽明復健診所",
  "type": "rehab",
  "reminder_minutes": 60,
  "note": "帶護膝"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "evt3c4d5-e6f7-8901-cdef-123456789012",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "title": "復健治療",
    "title_translated": {
      "zh-TW": "復健治療",
      "id": "Terapi rehabilitasi"
    },
    "start_time": "2026-04-16T14:00:00Z",
    "end_time": "2026-04-16T15:00:00Z",
    "location": "陽明復健診所",
    "type": "rehab",
    "reminder_minutes": 60,
    "note": "帶護膝",
    "source": "manual",
    "source_id": null,
    "created_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "created_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### PUT /events/:id/

更新行事曆事件。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "title": "復健治療（改時間）",
  "start_time": "2026-04-16T15:00:00Z",
  "end_time": "2026-04-16T16:00:00Z",
  "reminder_minutes": 30
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "evt3c4d5-e6f7-8901-cdef-123456789012",
    "title": "復健治療（改時間）",
    "start_time": "2026-04-16T15:00:00Z",
    "end_time": "2026-04-16T16:00:00Z",
    "reminder_minutes": 30,
    "created_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### DELETE /events/:id/

刪除行事曆事件。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（204 No Content）：**

無回應內容。

---

### POST /events/batch/

批次建立行事曆事件。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "events": [
    {
      "title": "復健治療",
      "start_time": "2026-04-16T14:00:00Z",
      "end_time": "2026-04-16T15:00:00Z",
      "location": "陽明復健診所",
      "type": "rehab",
      "reminder_minutes": 60
    },
    {
      "title": "回診 - 台大心臟內科",
      "start_time": "2026-04-20T09:00:00Z",
      "end_time": "2026-04-20T11:00:00Z",
      "location": "台大醫院",
      "type": "medical",
      "reminder_minutes": 60
    }
  ]
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "created": 2,
    "events": [
      {
        "id": "evt4d5e6-f7a8-9012-cdef-123456789012",
        "title": "復健治療"
      },
      {
        "id": "evt5e6f7-a8b9-0123-cdef-123456789012",
        "title": "回診 - 台大心臟內科"
      }
    ]
  }
}
```

---

## 11. Todo 代辦事項

### GET /todos/

取得代辦事項列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `status` | String | 篩選狀態：`pending` / `completed` |
| `priority` | String | 篩選優先度：`high` / `medium` / `low` |
| `assignee` | UUID | 指派對象 ID |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "td1a2b3c-d4e5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "title": "帶爺爺去公園散步",
      "title_translated": {
        "zh-TW": "帶爺爺去公園散步",
        "id": "Ajak kakek jalan-jalan di taman"
      },
      "assignee": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "priority": "medium",
      "status": "pending",
      "due_date": "2026-04-12",
      "completed_at": null,
      "care_log": null,
      "created_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-04-12T07:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 8
  }
}
```

---

### POST /todos/

建立代辦事項（推播通知被指派者）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "title": "量血壓",
  "assignee_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "priority": "high",
  "due_date": "2026-04-12"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "td2b3c4d-e5f6-7890-bcde-f12345678901",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "title": "量血壓",
    "title_translated": {
      "zh-TW": "量血壓",
      "id": "Ukur tekanan darah"
    },
    "assignee": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "priority": "high",
    "status": "pending",
    "due_date": "2026-04-12",
    "created_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "created_at": "2026-04-12T07:00:00Z"
  }
}
```

---

### PUT /todos/:id/

更新代辦事項（完成時自動建立 care_log 活動紀錄）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body（標記完成）：**

```json
{
  "status": "completed"
}
```

**Request Body（更新內容）：**

```json
{
  "title": "量血壓並記錄",
  "priority": "high",
  "due_date": "2026-04-13"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "td2b3c4d-e5f6-7890-bcde-f12345678901",
    "title": "量血壓",
    "status": "completed",
    "completed_at": "2026-04-12T10:30:00Z",
    "care_log": {
      "id": "cl5e6f7a-b8c9-0123-cdef-123456789012"
    }
  }
}
```

---

### DELETE /todos/:id/

刪除代辦事項。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（204 No Content）：**

無回應內容。

---

## 12. Document 文件管理

### GET /documents/

取得文件列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `category` | String | 篩選分類：`insurance` / `medical` / `id_document` / `contract` / `other` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "doc1a2b3-c4d5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "title": "健保卡正面",
      "category": "id_document",
      "file_size": 524288,
      "mime_type": "image/jpeg",
      "uploaded_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-04-01T08:00:00Z"
    },
    {
      "id": "doc2b3c4-d5e6-7890-bcde-f12345678901",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "title": "長照保險單",
      "category": "insurance",
      "file_size": 1048576,
      "mime_type": "application/pdf",
      "uploaded_by": {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明"
      },
      "created_at": "2026-03-15T10:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 6
  }
}
```

---

### POST /documents/

上傳文件（multipart/form-data，上傳至 S3，檔案大小限制 10MB）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body（multipart/form-data）：**

```
title: 診斷證明書
category: medical
file: <binary file>
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "doc3c4d5-e6f7-8901-cdef-123456789012",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "title": "診斷證明書",
    "category": "medical",
    "file_url": "https://carebridge-storage.s3.amazonaws.com/documents/doc3c4d5.pdf",
    "file_size": 256000,
    "mime_type": "application/pdf",
    "uploaded_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "created_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### GET /documents/:id/

取得文件詳情（包含 Presigned URL，有效期 1 小時）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "doc3c4d5-e6f7-8901-cdef-123456789012",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "title": "診斷證明書",
    "category": "medical",
    "file_url": "https://carebridge-storage.s3.ap-northeast-1.amazonaws.com/documents/doc3c4d5.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Expires=3600&...",
    "file_size": 256000,
    "mime_type": "application/pdf",
    "uploaded_by": {
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "王小明"
    },
    "created_at": "2026-04-12T10:00:00Z"
  }
}
```

---

### DELETE /documents/:id/

刪除文件（同時刪除 DB 紀錄與 S3 檔案）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Response（204 No Content）：**

無回應內容。

---

## 13. AI 智慧助理

### POST /ai/chat/

AI 對話式查詢（SSE 串流回應，支援 Function Calling 查詢照護、健康、用藥、消費、行事曆數據）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |
| 回應類型 | `text/event-stream`（SSE） |

**Request Body：**

```json
{
  "message": "爺爺最近一週的血壓如何？",
  "conversation_id": "ai1a2b3c-d4e5-6789-abcd-ef1234567890"
}
```

**Response（SSE 串流）：**

```
data: {"type": "token", "content": "根據"}
data: {"type": "token", "content": "最近"}
data: {"type": "token", "content": "一週"}
data: {"type": "token", "content": "的"}
data: {"type": "token", "content": "紀錄"}
data: {"type": "token", "content": "，"}
data: {"type": "token", "content": "爺爺"}
data: {"type": "token", "content": "的"}
data: {"type": "token", "content": "收縮壓"}
data: {"type": "token", "content": "平均"}
data: {"type": "token", "content": "為"}
data: {"type": "token", "content": " 126.5 mmHg"}
data: {"type": "token", "content": "..."}
data: {"type": "done", "conversation_id": "ai1a2b3c-d4e5-6789-abcd-ef1234567890", "tokens_used": 350}
```

---

### POST /ai/care-analysis/

照護記錄分析（取得照護摘要 → GPT-4o 產生分析報告）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "start_date": "2026-04-06",
  "end_date": "2026-04-12"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "period": {
      "start_date": "2026-04-06",
      "end_date": "2026-04-12"
    },
    "analysis": "本週照護概況：\n\n1. 用藥順從度 85.7%（12/14 次），建議持續關注漏服情形...\n2. 生理數值穩定，收縮壓平均 126.5 mmHg，舒張壓平均 80.3 mmHg...\n3. 飲食狀況良好，18 餐中有 12 餐食慾良好...\n4. 活動量適中，每日平均步行 30 分鐘...",
    "recommendations": [
      "建議加強 20:00 時段的用藥提醒",
      "血壓偏高，建議下次回診時與醫師討論",
      "可適當增加戶外活動時間"
    ]
  }
}
```

---

### POST /ai/handover-report/

看護交接報告生成（彙整照護資料 → GPT-4o 產生雙語報告）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Request Body：**

```json
{
  "start_date": "2026-04-06",
  "end_date": "2026-04-12",
  "format": "json"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "report": {
      "title": "照護交接報告 2026/04/06 - 2026/04/12",
      "elder_name": "王大明",
      "sections": {
        "medication": "本週用藥順從度 85.7%，漏服 2 次（4/8 晚間、4/10 晚間）...",
        "vitals": "生理數值穩定，血壓平均 126/80 mmHg...",
        "meals": "飲食正常，食慾良好...",
        "activities": "每日散步 30 分鐘，復健治療 2 次...",
        "notes": "4/10 精神狀況較差，已加強觀察..."
      },
      "sections_translated": {
        "medication": "Kepatuhan obat minggu ini 85.7%, terlewat 2 kali...",
        "vitals": "Data fisiologis stabil, tekanan darah rata-rata 126/80 mmHg...",
        "meals": "Makan normal, nafsu makan baik...",
        "activities": "Jalan kaki harian 30 menit, terapi rehabilitasi 2 kali...",
        "notes": "Tanggal 10/4 semangat kurang baik, sudah diperhatikan lebih..."
      }
    },
    "pdf_url": "https://carebridge-storage.s3.amazonaws.com/reports/rpt_20260412.pdf"
  }
}
```

---

### POST /ai/subsidy-form/

政府補助表單自動填寫（GPT-4o 根據長者資料填寫 → 標記缺漏欄位 → 產生 PDF）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | family_member |

**Request Body：**

```json
{
  "form_type": "long_term_care",
  "additional_info": {
    "disability_level": "moderate",
    "care_needs": "daily_living_assistance"
  }
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "form_type": "long_term_care",
    "filled_fields": {
      "applicant_name": "王大明",
      "birth_date": "1945-03-15",
      "id_number": null,
      "address": null,
      "disability_level": "moderate",
      "care_needs": "daily_living_assistance"
    },
    "missing_fields": ["id_number", "address", "phone", "emergency_contact"],
    "pdf_url": "https://carebridge-storage.s3.amazonaws.com/forms/form_20260412.pdf"
  }
}
```

---

### POST /ai/first-aid/

急救指引 RAG 查詢（使用者問題 → Embedding → pgvector 相似度搜尋 → GPT-4o 產生急救指引）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Request Body：**

```json
{
  "query": "長者跌倒後頭部有外傷，意識清楚，該怎麼處理？"
}
```

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "answer": "根據衛福部急救手冊建議：\n\n1. 保持冷靜，不要移動傷者\n2. 檢查意識狀態和呼吸\n3. 如有出血，以乾淨紗布輕壓止血\n4. 冰敷腫脹部位（隔布冰敷，每次不超過 15 分鐘）\n5. 即使意識清楚，仍建議就醫檢查是否有腦震盪\n6. 觀察 24-48 小時內是否出現嘔吐、頭痛加劇、嗜睡等症狀\n\n**緊急狀況**：若出現意識模糊、持續嘔吐、瞳孔大小不一，請立即撥打 119。",
    "sources": [
      {
        "title": "老人跌倒急救處理指南",
        "source": "衛生福利部",
        "section": "頭部外傷處理"
      },
      {
        "title": "居家照護急救手冊",
        "source": "衛生福利部",
        "section": "跌倒處理流程"
      }
    ]
  }
}
```

---

## 14. SOS 緊急呼叫

### POST /sos/trigger/

觸發 SOS 緊急呼叫（儲存紀錄 → 推播通知所有家庭成員，高優先級 APNs）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / elder |

**Request Body：**

```json
{
  "location": {
    "latitude": 25.0330,
    "longitude": 121.5654,
    "address": "台北市信義區信義路五段7號"
  },
  "situation": "爺爺在浴室跌倒",
  "auto_call_119": true
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "sos1a2b3-c4d5-6789-abcd-ef1234567890",
    "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "triggered_by": {
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "Siti"
    },
    "location": {
      "latitude": 25.0330,
      "longitude": 121.5654,
      "address": "台北市信義區信義路五段7號"
    },
    "situation": "爺爺在浴室跌倒",
    "auto_call_119": true,
    "notified_members": [
      {
        "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "name": "王小明",
        "notified": true
      }
    ],
    "status": "triggered",
    "triggered_at": "2026-04-12T14:00:00Z"
  }
}
```

---

### GET /sos/history/

SOS 歷史紀錄列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `status` | String | 篩選狀態：`triggered` / `resolved` |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "sos1a2b3-c4d5-6789-abcd-ef1234567890",
      "family": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "triggered_by": {
        "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "name": "Siti"
      },
      "location": {
        "latitude": 25.0330,
        "longitude": 121.5654,
        "address": "台北市信義區信義路五段7號"
      },
      "situation": "爺爺在浴室跌倒",
      "auto_call_119": true,
      "notified_members": [
        {
          "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "name": "王小明",
          "notified": true
        }
      ],
      "status": "resolved",
      "triggered_at": "2026-04-12T14:00:00Z",
      "resolved_at": "2026-04-12T14:30:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 1
  }
}
```

---

## 15. Notification 通知系統

### GET /notifications/

取得通知列表。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Query 參數：**

| 參數 | 型別 | 說明 |
|---|---|---|
| `is_read` | Boolean | 篩選已讀/未讀 |
| `type` | String | 通知類型篩選 |
| `page` | Integer | 頁碼 |
| `page_size` | Integer | 每頁筆數 |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": [
    {
      "id": "nf1a2b3c-d4e5-6789-abcd-ef1234567890",
      "user": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "type": "health_alert",
      "title": "健康警示：心率異常",
      "title_translated": {
        "zh-TW": "健康警示：心率異常",
        "id": "Peringatan kesehatan: detak jantung tidak normal"
      },
      "body": "長者心率達到 112 bpm，超過上限 100 bpm",
      "body_translated": {
        "zh-TW": "長者心率達到 112 bpm，超過上限 100 bpm",
        "id": "Detak jantung lansia mencapai 112 bpm, melebihi batas 100 bpm"
      },
      "data": {
        "alert_id": "ha1a2b3c-d4e5-6789-abcd-ef1234567890",
        "route": "/health/alerts"
      },
      "is_read": false,
      "read_at": null,
      "created_at": "2026-04-12T11:30:00Z"
    },
    {
      "id": "nf2b3c4d-e5f6-7890-bcde-f12345678901",
      "user": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "type": "medication_confirmed",
      "title": "用藥確認：Amlodipine 5mg",
      "title_translated": {
        "zh-TW": "用藥確認：Amlodipine 5mg",
        "id": "Konfirmasi obat: Amlodipine 5mg"
      },
      "body": "Siti 已確認完成 08:00 用藥",
      "body_translated": {
        "zh-TW": "Siti 已確認完成 08:00 用藥",
        "id": "Siti telah mengkonfirmasi pemberian obat pukul 08:00"
      },
      "data": {
        "medication_id": "med1a2b3-c4d5-6789-abcd-ef1234567890",
        "route": "/medications"
      },
      "is_read": true,
      "read_at": "2026-04-12T09:00:00Z",
      "created_at": "2026-04-12T08:15:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 20,
    "total": 15
  }
}
```

---

### PUT /notifications/:id/read/

標記單則通知為已讀。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "id": "nf1a2b3c-d4e5-6789-abcd-ef1234567890",
    "is_read": true,
    "read_at": "2026-04-12T12:00:00Z"
  }
}
```

---

### PUT /notifications/read-all/

標記所有通知為已讀。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Response（200 OK）：**

```json
{
  "success": true,
  "data": {
    "updated_count": 8
  }
}
```

---

### POST /notifications/device/

註冊裝置推播 Token（APNs）。

| 項目 | 說明 |
|---|---|
| 認證 | 是 |
| 權限 | caregiver / family_member / elder |

**Request Body：**

```json
{
  "device_token": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
  "platform": "ios",
  "device_name": "iPhone 16 Pro"
}
```

**Response（201 Created）：**

```json
{
  "success": true,
  "data": {
    "id": "dev1a2b3-c4d5-6789-abcd-ef1234567890",
    "user": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "device_token": "a1b2c3d4e5f6...f0a1b2",
    "platform": "ios",
    "device_name": "iPhone 16 Pro",
    "is_active": true,
    "created_at": "2026-04-12T08:00:00Z"
  }
}
```

---

## 附錄

### A. 跨模組自動觸發規則

| 觸發動作 | 來源模組 | 目標模組 | 說明 |
|---|---|---|---|
| 餵藥拍照確認 | Medication | Care Log | 自動建立 `type=medication` 的照護日誌 |
| 完成代辦事項 | Todo | Care Log | 自動建立 `type=activity` 的照護日誌 |
| 新增藥物 | Medication | Calendar Event | 自動建立用藥提醒行事曆（`source=medication`） |
| 核准請假 | Leave | Calendar Event | 自動建立請假行事曆（`source=leave`） |
| 健康數據同步 | Health | Health Alert | 數值超過閾值時自動建立異常警示 |
| 健康數據異常 | Health Alert | Notification | 推播通知所有家庭成員 |
| 用藥到時 | Medication（Celery Beat） | Notification | 推播提醒看護 + Watch |
| 看護確認餵藥 | Medication Confirm | Notification | 推播通知家屬 |
| 看護申請請假 | Leave | Notification | 推播通知家屬 |
| 請假核准/駁回 | Leave | Notification | 推播通知看護 |
| 看護發送採購需求 | Board | Notification | 推播通知家屬 |
| 家屬確認採購 | Board | Notification | 推播通知看護 |
| 收據 OCR 完成 | Expense（Celery） | Notification | 推播通知看護 |
| SOS 觸發 | SOS | Notification | 推播通知所有家庭成員（高優先級） |
| 行程前提醒 | Calendar Event（Celery Beat） | Notification | 提前 N 分鐘推播 |
| 代辦被指派 | Todo | Notification | 推播通知被指派者 |
| 聊天訊息（離線） | Chat | Notification | 推播通知離線接收者 |

---

### B. 角色權限矩陣

| 端點 | caregiver | family_member | elder |
|---|---|---|---|
| **Auth** | | | |
| POST /auth/register/ | O | O | O |
| POST /auth/login/ | O | O | O |
| GET /auth/me/ | O | O | O |
| PUT /auth/me/ | O | O | O |
| DELETE /auth/account/ | O | O | O |
| **Family** | | | |
| POST /families/ | - | O | - |
| GET /families/:id/ | O | O | O |
| POST /families/:id/members/ | O | O | O |
| DELETE /families/:id/members/:userId/ | - | O (primary) | - |
| **Chat** | | | |
| GET /chats/ | O | O | O |
| POST /chats/ | O | O | O |
| GET /chats/:id/messages/ | O | O | O |
| POST /chats/:id/messages/ | O | O | O |
| **Board** | | | |
| GET /board/ | O | O | - |
| POST /board/ | O | - | - |
| PUT /board/:id/ | O | - | - |
| PATCH /board/:id/status/ | - | O | - |
| **Care Log** | | | |
| GET /care-logs/ | O | O | - |
| POST /care-logs/ | O | - | - |
| PUT /care-logs/:id/ | O | - | - |
| GET /care-logs/summary/ | O | O | - |
| **Medication** | | | |
| GET /medications/ | O | O | - |
| POST /medications/ | - | O | - |
| PUT /medications/:id/ | - | O | - |
| GET /medications/today_confirmations/ | O | O | O |
| POST /medications/:id/confirm/ | O | O | - |
| **Expense** | | | |
| GET /expenses/ | O | O | - |
| POST /expenses/scan/ | O | - | - |
| GET /expenses/:id/ | O | O | - |
| PUT /expenses/:id/ | O | O | - |
| GET /expenses/monthly/ | O | O | - |
| **Leave** | | | |
| GET /leaves/ | O | O | - |
| POST /leaves/ | O | - | - |
| PATCH /leaves/:id/status/ | - | O | - |
| **Health** | | | |
| POST /health-data/sync/ | O | - | O |
| GET /health-data/ | O | O | O |
| GET /health-data/dashboard/ | O | O | O |
| GET /health-data/alerts/ | O | O | - |
| PUT /health-data/alerts/:id/acknowledge/ | O | O | - |
| PUT /health-data/thresholds/ | - | O | - |
| GET /health-data/weekly-steps/ | O | O | O |
| **Calendar Event** | | | |
| GET /events/ | O | O | O |
| POST /events/ | O | O | - |
| PUT /events/:id/ | O | O | - |
| DELETE /events/:id/ | O | O | - |
| POST /events/batch/ | O | O | - |
| **Todo** | | | |
| GET /todos/ | O | O | - |
| POST /todos/ | O | O | - |
| PUT /todos/:id/ | O | O | - |
| DELETE /todos/:id/ | O | O | - |
| **Document** | | | |
| GET /documents/ | O | O | - |
| POST /documents/ | O | O | - |
| GET /documents/:id/ | O | O | - |
| DELETE /documents/:id/ | - | O | - |
| **AI** | | | |
| POST /ai/chat/ | O | O | - |
| POST /ai/care-analysis/ | O | O | - |
| POST /ai/handover-report/ | O | O | - |
| POST /ai/subsidy-form/ | - | O | - |
| POST /ai/first-aid/ | O | O | O |
| **SOS** | | | |
| POST /sos/trigger/ | O | - | O |
| GET /sos/history/ | O | O | - |
| **Notification** | | | |
| GET /notifications/ | O | O | O |
| PUT /notifications/:id/read/ | O | O | O |
| PUT /notifications/read-all/ | O | O | O |
| POST /notifications/device/ | O | O | O |

> **O** = 可存取 / **-** = 無權限

---

### C. WebSocket 訊息格式（Chat）

#### 連線方式

```
ws://127.0.0.1:8000/ws/chat/<chat_id>/?token=<access_token>
```

#### 客戶端 → 伺服器

| action | 說明 | 資料格式 |
|---|---|---|
| `message` | 發送訊息 | `{"action": "message", "data": {"type": "text", "content": "..."}}` |
| `message` | 發送圖片 | `{"action": "message", "data": {"type": "image", "image_url": "..."}}` |
| `typing` | 正在輸入 | `{"action": "typing", "data": {"is_typing": true}}` |

#### 伺服器 → 客戶端

| action | 說明 | 資料格式 |
|---|---|---|
| `message` | 接收訊息 | `{"action": "message", "data": {"id": "...", "sender": {...}, "type": "text", "content": "...", "translations": {...}, "sent_at": "..."}}` |
| `typing` | 對方正在輸入 | `{"action": "typing", "data": {"user_id": "...", "is_typing": true}}` |
| `error` | 錯誤訊息 | `{"action": "error", "data": {"code": "...", "message": "..."}}` |

#### 事件類型

| 事件 | Channel Layer 事件名稱 | 說明 |
|---|---|---|
| 訊息廣播 | `chat.message` | 新訊息廣播至所有聊天室成員 |
| 輸入狀態 | `chat.typing` | 「正在輸入」狀態轉發 |

---

### D. 通知類型一覽

| 通知類型 | 說明 | 接收者 |
|---|---|---|
| `health_alert` | 健康數據異常警示 | 全部家庭成員 |
| `medication_reminder` | 用藥時間提醒 | 看護 + Watch |
| `medication_confirmed` | 看護已確認餵藥 | 家屬 |
| `leave_request` | 看護申請請假 | 家屬 |
| `leave_approved` | 請假已核准 | 看護 |
| `leave_rejected` | 請假已駁回 | 看護 |
| `board_request` | 新採購需求 | 家屬 |
| `board_approved` | 採購需求已確認 | 看護 |
| `expense_scanned` | 收據 OCR 辨識完成 | 看護 |
| `sos_triggered` | SOS 緊急呼叫 | 全部家庭成員 |
| `event_reminder` | 行程前提醒 | 對應成員 |
| `todo_assigned` | 被指派新代辦 | 被指派者 |
| `chat_message` | 聊天訊息（離線推播） | 接收者 |
