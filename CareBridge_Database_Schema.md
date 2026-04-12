# CareBridge 照護橋 — Database Schema 設計文件

> **版本**: v1.0
> **最後更新**: 2026/04/11
> **資料庫**: PostgreSQL 16 + pgvector 擴展
> **ORM**: Django ORM
> **對應功能清單**: CareBridge_Feature_List v1.1（96 項功能）

---

## ER 關聯總覽

```
                          ┌──────────────┐
                          │    users     │
                          │──────────────│
                          │ PK id        │
                          │ email        │
                          │ role         │
                          │ language     │
                          │ FK family_id │──────┐
                          └──────┬───────┘      │
                                 │              │
            ┌────────────────────┼──────────────┼──────────────────┐
            │                    │              │                  │
            ▼                    ▼              ▼                  ▼
   ┌─────────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────────┐
   │    devices       │  │   families   │  │  chats   │  │ ai_convers.  │
   │─────────────────│  │──────────────│  │──────────│  │──────────────│
   │ FK user_id      │  │ PK id        │  │ PK id    │  │ FK user_id   │
   │ device_token    │  │ name         │  │ type     │  │ FK family_id │
   │ platform        │  │ elder_name   │  │ FK fam_id│  │ messages_hist│
   └─────────────────┘  │ invite_code  │  └────┬─────┘  └──────────────┘
                         └──────┬───────┘       │
                                │               ▼
          ┌─────────────────────┼──────┐  ┌──────────────┐
          │                     │      │  │   messages    │
          ▼                     ▼      │  │──────────────│
  ┌──────────────┐  ┌───────────────┐  │  │ FK chat_id   │
  │  care_logs   │  │  medications  │  │  │ FK sender_id │
  │──────────────│  │───────────────│  │  │ type         │
  │ FK family_id │  │ FK family_id  │  │  │ content      │
  │ FK recorder  │  │ name          │  │  │ translations │
  │ type         │  │ dosage        │  │  └──────────────┘
  │ content(JSON)│  │ times(JSON)   │  │
  │ photo_url    │  │ active        │  │  ┌──────────────────────┐
  └──────────────┘  └───────┬───────┘  │  │  board_requests      │
                            │          │  │──────────────────────│
                            ▼          │  │ FK family_id         │
                   ┌─────────────────┐ │  │ FK requester_id      │
                   │ med_confirms    │ │  │ items (JSON)         │
                   │─────────────────│ │  │ status               │
                   │ FK medication_id│ │  └──────────────────────┘
                   │ FK confirmed_by │ │
                   │ photo_url      │ │  ┌──────────────────────┐
                   │ care_log_id    │ │  │  expenses             │
                   └─────────────────┘ │  │──────────────────────│
                                       │  │ FK family_id         │
  ┌──────────────┐  ┌───────────────┐  │  │ FK recorder_id       │
  │ health_data  │  │ health_alerts │  │  │ items (JSON)         │
  │──────────────│  │───────────────│  │  │ total_amount         │
  │ FK family_id │  │ FK family_id  │  │  │ image_url            │
  │ type         │  │ type          │  │  └──────────────────────┘
  │ value        │  │ value         │  │
  │ recorded_at  │  │ severity      │  │  ┌──────────────────────┐
  └──────────────┘  │ acknowledged  │  │  │  leaves              │
                    └───────────────┘  │  │──────────────────────│
                                       │  │ FK family_id         │
  ┌──────────────┐  ┌───────────────┐  │  │ FK applicant_id      │
  │   events     │  │    todos      │  │  │ type, status         │
  │──────────────│  │───────────────│  │  │ start_date, end_date │
  │ FK family_id │  │ FK family_id  │  │  └──────────────────────┘
  │ title        │  │ FK assignee   │  │
  │ start_time   │  │ FK created_by │  │  ┌──────────────────────┐
  │ type         │  │ priority      │  │  │  documents           │
  └──────────────┘  │ status        │  │  │──────────────────────│
                    └───────────────┘  │  │ FK family_id         │
                                       │  │ FK uploaded_by       │
  ┌──────────────┐  ┌───────────────┐  │  │ file_url, category   │
  │notifications │  │  sos_records  │  │  └──────────────────────┘
  │──────────────│  │───────────────│  │
  │ FK user_id   │  │ FK family_id  │──┘
  │ type         │  │ FK trigger_by │
  │ title, body  │  │ location(JSON)│
  │ read         │  │ status        │
  └──────────────┘  └───────────────┘

  ┌────────────────────────┐
  │  first_aid_documents   │
  │────────────────────────│
  │ title, content         │
  │ source                 │
  │ embedding (vector)     │  ← pgvector
  └────────────────────────┘
```

---

## 資料表定義

### 1. users（使用者）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK, default uuid4 | 使用者唯一識別碼 |
| `email` | VARCHAR(255) | UNIQUE, NOT NULL | 電子郵件（登入帳號） |
| `password` | VARCHAR(128) | NOT NULL | 密碼 hash（Django 內建） |
| `name` | VARCHAR(100) | NOT NULL | 姓名 |
| `role` | VARCHAR(20) | NOT NULL | 角色：`caregiver` / `family_member` / `elder` |
| `language` | VARCHAR(10) | NOT NULL, DEFAULT 'zh-TW' | 語言偏好：`zh-TW` / `id` / `vi` / `tl` |
| `phone` | VARCHAR(20) | NULL | 電話號碼 |
| `avatar_url` | VARCHAR(500) | NULL | 頭像 S3 URL |
| `family_id` | UUID | FK → families.id, NULL | 所屬家庭（未加入時為 NULL） |
| `is_primary` | BOOLEAN | DEFAULT false | 是否為家庭主要管理者 |
| `is_active` | BOOLEAN | DEFAULT true | 帳號是否啟用 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**索引**:
- `UNIQUE INDEX idx_users_email ON users(email)`
- `INDEX idx_users_family ON users(family_id)`

**對應功能**: 1.1–1.8（認證與帳號）

---

### 2. families（家庭群組）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 家庭唯一識別碼 |
| `name` | VARCHAR(100) | NOT NULL | 家庭名稱 |
| `elder_name` | VARCHAR(100) | NOT NULL | 長者姓名 |
| `elder_birth_date` | DATE | NULL | 長者生日 |
| `invite_code` | VARCHAR(10) | UNIQUE, NOT NULL | 邀請碼（8 位英數） |
| `created_by` | UUID | FK → users.id | 建立者 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `UNIQUE INDEX idx_families_invite ON families(invite_code)`

**對應功能**: 2.1–2.4（家庭管理）

---

### 3. chats（聊天室）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 聊天室唯一識別碼 |
| `type` | VARCHAR(10) | NOT NULL | 類型：`group` / `direct` |
| `name` | VARCHAR(100) | NULL | 群組名稱（group 時使用） |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**對應功能**: 4.1–4.2（群組/一對一聊天）

---

### 4. chat_members（聊天室成員）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | BIGINT | PK, AUTO | 自動遞增 ID |
| `chat_id` | UUID | FK → chats.id | 聊天室 |
| `user_id` | UUID | FK → users.id | 成員 |
| `joined_at` | TIMESTAMP | DEFAULT now() | 加入時間 |

**約束**: `UNIQUE(chat_id, user_id)`

---

### 5. messages（聊天訊息）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 訊息唯一識別碼 |
| `chat_id` | UUID | FK → chats.id, NOT NULL | 所屬聊天室 |
| `sender_id` | UUID | FK → users.id, NOT NULL | 發送者 |
| `type` | VARCHAR(10) | NOT NULL | 類型：`text` / `image` |
| `content` | TEXT | NULL | 文字內容（text 類型）或圖說（image 類型） |
| `translations` | JSONB | NULL | 翻譯結果，格式：`{"id": "...", "zh-TW": "..."}` |
| `image_url` | VARCHAR(500) | NULL | 圖片 S3 URL（image 類型） |
| `sent_at` | TIMESTAMP | DEFAULT now() | 發送時間 |

**索引**:
- `INDEX idx_messages_chat_time ON messages(chat_id, sent_at DESC)`

**對應功能**: 4.3–4.5（文字/圖片/語音訊息）

---

### 6. board_requests（留言板 — 採購需求）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 需求唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `requester_id` | UUID | FK → users.id | 發起者（看護） |
| `category` | VARCHAR(20) | NOT NULL | 分類：`food` / `daily` / `medical` / `other` |
| `items` | JSONB | NOT NULL | 品項清單：`[{"name": "...", "name_translated": "...", "quantity": "..."}]` |
| `note` | TEXT | NULL | 備註 |
| `note_translated` | TEXT | NULL | 備註翻譯 |
| `status` | VARCHAR(20) | NOT NULL, DEFAULT 'pending' | 狀態：`pending` / `approved` / `rejected` / `completed` |
| `reply` | TEXT | NULL | 家屬回覆訊息 |
| `reviewed_by` | UUID | FK → users.id, NULL | 審核者 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**索引**:
- `INDEX idx_board_family_status ON board_requests(family_id, status)`

**對應功能**: 5.1–5.4（留言板）

---

### 7. care_logs（照護日誌）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 紀錄唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `recorder_id` | UUID | FK → users.id | 紀錄者 |
| `type` | VARCHAR(20) | NOT NULL | 類型：`medication` / `vital` / `meal` / `activity` / `note` |
| `content` | JSONB | NOT NULL | 紀錄內容（依 type 不同，見下方說明） |
| `photo_url` | VARCHAR(500) | NULL | 照片 S3 URL |
| `timestamp` | TIMESTAMP | NOT NULL | 紀錄時間 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**content JSONB 欄位格式**：

```jsonc
// type = "medication"
{
  "medication_name": "Amlodipine 5mg",
  "dosage": "1 顆",
  "status": "taken",
  "confirmed_by": "usr_xxx",
  "confirmed_at": "2026-04-08T08:15:00Z"
}

// type = "vital"
{
  "blood_pressure_systolic": 128,
  "blood_pressure_diastolic": 82,
  "blood_sugar": 5.8,
  "temperature": 36.5,
  "note": "狀況穩定"
}

// type = "meal"
{
  "meal_type": "breakfast",       // breakfast / lunch / dinner / snack
  "description": "雞肉粥",
  "description_translated": "Bubur ayam",
  "appetite": "good"             // good / fair / poor
}

// type = "activity"
{
  "activity_type": "walking",
  "duration_minutes": 30,
  "note": "公園散步"
}

// type = "note"
{
  "text": "今天精神不錯",
  "text_translated": "Hari ini semangatnya baik"
}
```

**索引**:
- `INDEX idx_carelog_family_time ON care_logs(family_id, timestamp DESC)`
- `INDEX idx_carelog_family_type ON care_logs(family_id, type)`

**對應功能**: 6.1–6.7（照護日誌）
**跨模組連動**:
- 餵藥確認（7.4）自動建立 type=medication 紀錄
- 完成代辦（12.3）自動建立 type=activity 紀錄

---

### 8. medications（藥物管理）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 藥物唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `name` | VARCHAR(200) | NOT NULL | 藥物名稱 |
| `name_translated` | JSONB | NULL | 翻譯：`{"id": "...", "zh-TW": "..."}` |
| `dosage` | VARCHAR(50) | NOT NULL | 劑量（如 "1 顆"） |
| `frequency` | VARCHAR(20) | NOT NULL | 頻率：`daily` / `twice_daily` / `weekly` / `as_needed` |
| `times` | JSONB | NOT NULL | 服藥時間：`["08:00", "20:00"]` |
| `instructions` | TEXT | NULL | 服用注意事項 |
| `instructions_translated` | JSONB | NULL | 注意事項翻譯 |
| `start_date` | DATE | NOT NULL | 開始日期 |
| `end_date` | DATE | NULL | 結束日期（NULL = 長期服用） |
| `is_active` | BOOLEAN | DEFAULT true | 是否啟用 |
| `reminder_enabled` | BOOLEAN | DEFAULT true | 是否開啟提醒 |
| `created_by` | UUID | FK → users.id | 建立者（家屬） |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**索引**:
- `INDEX idx_med_family_active ON medications(family_id, is_active)`

**對應功能**: 7.1–7.6（用藥管理）

---

### 9. medication_confirmations（餵藥確認）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 確認唯一識別碼 |
| `medication_id` | UUID | FK → medications.id | 對應藥物 |
| `confirmed_by` | UUID | FK → users.id | 確認者（看護） |
| `photo_url` | VARCHAR(500) | NOT NULL | 餵藥照片 S3 URL |
| `scheduled_time` | VARCHAR(5) | NOT NULL | 排定時間（如 "08:00"） |
| `note` | TEXT | NULL | 備註 |
| `care_log_id` | UUID | FK → care_logs.id, NULL | 自動建立的照護日誌紀錄 ID |
| `confirmed_at` | TIMESTAMP | DEFAULT now() | 確認時間 |

**對應功能**: 7.4（餵藥拍照確認）
**跨模組連動**: 建立時自動建立 care_logs 紀錄（type=medication）

---

### 10. expenses（消費紀錄）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 紀錄唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `recorder_id` | UUID | FK → users.id | 紀錄者 |
| `scan_id` | VARCHAR(50) | NULL | OCR 掃描任務 ID |
| `store_name` | VARCHAR(200) | NULL | 商店名稱 |
| `date` | DATE | NOT NULL | 消費日期 |
| `items` | JSONB | NOT NULL | 品項明細：`[{"name": "...", "quantity": 1, "unit_price": 75, "total": 75, "category": "food"}]` |
| `total_amount` | DECIMAL(10,2) | NOT NULL | 總金額 |
| `image_url` | VARCHAR(500) | NULL | 收據照片 S3 URL |
| `ocr_confidence` | DECIMAL(3,2) | NULL | OCR 辨識信心度（0–1） |
| `status` | VARCHAR(20) | DEFAULT 'completed' | 狀態：`processing` / `completed` / `failed` |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**索引**:
- `INDEX idx_expense_family_date ON expenses(family_id, date DESC)`

**對應功能**: 8.1–8.5（消費記帳）

---

### 11. leaves（請假紀錄）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 紀錄唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `applicant_id` | UUID | FK → users.id | 申請者（看護） |
| `type` | VARCHAR(20) | NOT NULL | 假別：`personal` / `sick` / `emergency` |
| `start_date` | DATE | NOT NULL | 開始日期 |
| `end_date` | DATE | NOT NULL | 結束日期 |
| `days` | INTEGER | NOT NULL | 天數 |
| `reason` | TEXT | NOT NULL | 請假原因 |
| `reason_translated` | TEXT | NULL | 原因翻譯 |
| `status` | VARCHAR(20) | DEFAULT 'pending' | 狀態：`pending` / `approved` / `rejected` |
| `reply` | TEXT | NULL | 審核者回覆 |
| `reviewed_by` | UUID | FK → users.id, NULL | 審核者 |
| `reviewed_at` | TIMESTAMP | NULL | 審核時間 |
| `calendar_event_id` | UUID | FK → events.id, NULL | 自動建立的行事曆事件 ID |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `INDEX idx_leave_family_status ON leaves(family_id, status)`

**對應功能**: 9.1–9.4（請假管理）
**跨模組連動**: 核准時自動建立 events 行事曆事件

---

### 12. health_data（健康數據）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 資料唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `device_id` | VARCHAR(50) | NULL | Watch 裝置 ID |
| `type` | VARCHAR(20) | NOT NULL | 類型：`heart_rate` / `blood_oxygen` / `step_count` / `active_energy` |
| `value` | DECIMAL(10,2) | NOT NULL | 數值 |
| `unit` | VARCHAR(10) | NOT NULL | 單位：`bpm` / `%` / `steps` / `kcal` |
| `recorded_at` | TIMESTAMP | NOT NULL | 量測時間 |
| `created_at` | TIMESTAMP | DEFAULT now() | 寫入時間 |

**索引**:
- `UNIQUE INDEX idx_health_dedup ON health_data(family_id, type, recorded_at)` — 去重
- `INDEX idx_health_query ON health_data(family_id, type, recorded_at DESC)` — 查詢最佳化

**對應功能**: 10.1, 10.3, 10.4（Watch 數據同步、即時顯示、歷史圖表）

---

### 13. health_alert_thresholds（健康警示閾值）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 唯一識別碼 |
| `family_id` | UUID | FK → families.id, UNIQUE | 每家庭一組閾值 |
| `heart_rate_high` | INTEGER | DEFAULT 100 | 心率上限 (bpm) |
| `heart_rate_low` | INTEGER | DEFAULT 50 | 心率下限 (bpm) |
| `blood_oxygen_low` | DECIMAL(4,1) | DEFAULT 93.0 | 血氧下限 (%) |
| `updated_by` | UUID | FK → users.id | 最後更新者 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**對應功能**: 10.5（異常閾值設定）

---

### 14. health_alerts（健康異常警示）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 警示唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `type` | VARCHAR(20) | NOT NULL | 類型：`heart_rate` / `blood_oxygen` |
| `value` | DECIMAL(10,2) | NOT NULL | 異常數值 |
| `threshold` | DECIMAL(10,2) | NOT NULL | 觸發的閾值 |
| `severity` | VARCHAR(10) | NOT NULL | 嚴重度：`warning` / `critical` |
| `acknowledged_by` | UUID | FK → users.id, NULL | 確認者 |
| `acknowledged_at` | TIMESTAMP | NULL | 確認時間 |
| `recorded_at` | TIMESTAMP | NOT NULL | 異常發生時間 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `INDEX idx_alert_family_time ON health_alerts(family_id, recorded_at DESC)`

**對應功能**: 10.6–10.7（異常通知、異常紀錄）
**觸發時機**: health_data 同步時，數值超出 health_alert_thresholds → 自動建立

---

### 15. events（行事曆）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 行程唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `title` | VARCHAR(200) | NOT NULL | 標題 |
| `title_translated` | JSONB | NULL | 標題翻譯 |
| `start_time` | TIMESTAMP | NOT NULL | 開始時間 |
| `end_time` | TIMESTAMP | NULL | 結束時間 |
| `location` | VARCHAR(300) | NULL | 地點 |
| `type` | VARCHAR(20) | NOT NULL | 類型：`medical` / `medication` / `rehab` / `leave` / `personal` / `other` |
| `reminder_minutes` | INTEGER | DEFAULT 60 | 提前提醒分鐘數 |
| `note` | TEXT | NULL | 備註 |
| `source` | VARCHAR(20) | DEFAULT 'manual' | 來源：`manual` / `medication` / `leave` |
| `source_id` | UUID | NULL | 來源關聯 ID（medication_id 或 leave_id） |
| `created_by` | UUID | FK → users.id | 建立者 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `INDEX idx_event_family_time ON events(family_id, start_time)`

**對應功能**: 11.1–11.5（行事曆）
**自動建立來源**:
- `source='medication'`：用藥提醒排程（7.3 → 11.3）
- `source='leave'`：請假核准後（9.4 → 11）

---

### 16. todos（代辦事項）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 代辦唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `title` | VARCHAR(200) | NOT NULL | 標題 |
| `title_translated` | JSONB | NULL | 標題翻譯 |
| `assignee_id` | UUID | FK → users.id | 指派對象 |
| `priority` | VARCHAR(10) | DEFAULT 'medium' | 優先度：`high` / `medium` / `low` |
| `status` | VARCHAR(20) | DEFAULT 'pending' | 狀態：`pending` / `completed` |
| `due_date` | DATE | NULL | 到期日 |
| `completed_at` | TIMESTAMP | NULL | 完成時間 |
| `care_log_id` | UUID | FK → care_logs.id, NULL | 完成時自動建立的照護日誌 ID |
| `created_by` | UUID | FK → users.id | 建立者 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `INDEX idx_todo_family_status ON todos(family_id, status)`
- `INDEX idx_todo_assignee ON todos(assignee_id, status)`

**對應功能**: 12.1–12.3（代辦事項）
**跨模組連動**: 完成時自動建立 care_logs（type=activity）

---

### 17. documents（文件）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 文件唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `title` | VARCHAR(200) | NOT NULL | 文件標題 |
| `category` | VARCHAR(20) | NOT NULL | 分類：`insurance` / `medical` / `id_document` / `contract` / `other` |
| `file_url` | VARCHAR(500) | NOT NULL | S3 檔案 URL |
| `file_size` | INTEGER | NOT NULL | 檔案大小（bytes） |
| `mime_type` | VARCHAR(50) | NOT NULL | MIME 類型：`application/pdf` / `image/jpeg` / `image/png` |
| `uploaded_by` | UUID | FK → users.id | 上傳者 |
| `created_at` | TIMESTAMP | DEFAULT now() | 上傳時間 |

**對應功能**: 13.1–13.4（文件管理）

---

### 18. notifications（通知）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 通知唯一識別碼 |
| `user_id` | UUID | FK → users.id | 接收者 |
| `type` | VARCHAR(30) | NOT NULL | 通知類型（見下方列表） |
| `title` | VARCHAR(200) | NOT NULL | 標題 |
| `title_translated` | JSONB | NULL | 標題翻譯 |
| `body` | TEXT | NOT NULL | 內容 |
| `body_translated` | JSONB | NULL | 內容翻譯 |
| `data` | JSONB | NULL | 附加資料（deep link 用）：`{"action": "open_health_dashboard", "alert_id": "..."}` |
| `is_read` | BOOLEAN | DEFAULT false | 是否已讀 |
| `read_at` | TIMESTAMP | NULL | 已讀時間 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**通知 type 列表**：

| type | 說明 | 觸發時機 |
|---|---|---|
| `health_alert` | 健康異常警示 | Watch 數據超出閾值 |
| `medication_reminder` | 用藥提醒 | 到達排定服藥時間 |
| `medication_confirmed` | 餵藥確認 | 看護確認已餵藥 |
| `leave_request` | 請假申請 | 看護提出請假 |
| `leave_approved` | 請假核准 | 家屬核准 |
| `leave_rejected` | 請假駁回 | 家屬駁回 |
| `board_request` | 採購需求 | 看護發送需求 |
| `board_approved` | 需求確認 | 家屬確認 |
| `expense_scanned` | 收據掃描完成 | OCR 處理完畢 |
| `sos_triggered` | SOS 緊急呼叫 | 觸發 SOS |
| `event_reminder` | 行程提醒 | 行程前 N 分鐘 |
| `todo_assigned` | 代辦指派 | 被指派新任務 |
| `chat_message` | 新聊天訊息 | 收到訊息（離線時） |

**索引**:
- `INDEX idx_notif_user_read ON notifications(user_id, is_read, created_at DESC)`

**對應功能**: 17.1–17.5（通知系統）

---

### 19. devices（裝置 Token）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 裝置唯一識別碼 |
| `user_id` | UUID | FK → users.id | 擁有者 |
| `device_token` | VARCHAR(200) | NOT NULL | APNs Device Token |
| `platform` | VARCHAR(10) | NOT NULL | 平台：`ios` / `watchos` |
| `device_name` | VARCHAR(100) | NULL | 裝置名稱 |
| `is_active` | BOOLEAN | DEFAULT true | 是否啟用 |
| `created_at` | TIMESTAMP | DEFAULT now() | 註冊時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**約束**: `UNIQUE(user_id, device_token)`

**對應功能**: 17.1（APNs 推播註冊）

---

### 20. sos_records（SOS 紀錄）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | SOS 唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `triggered_by` | UUID | FK → users.id | 觸發者 |
| `location` | JSONB | NULL | GPS 位置：`{"latitude": 25.033, "longitude": 121.565, "accuracy": 10.0, "address": "..."}` |
| `situation` | TEXT | NULL | 狀況描述 |
| `auto_call_119` | BOOLEAN | DEFAULT true | 是否自動撥打 119 |
| `notified_members` | JSONB | NULL | 已通知的成員列表：`[{"id": "...", "notified_at": "..."}]` |
| `status` | VARCHAR(20) | DEFAULT 'triggered' | 狀態：`triggered` / `resolved` |
| `triggered_at` | TIMESTAMP | DEFAULT now() | 觸發時間 |
| `resolved_at` | TIMESTAMP | NULL | 解除時間 |

**對應功能**: 16.1–16.4（SOS 緊急呼叫）

---

### 21. ai_conversations（AI 對話）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 對話唯一識別碼 |
| `family_id` | UUID | FK → families.id | 所屬家庭 |
| `user_id` | UUID | FK → users.id | 使用者 |
| `messages_history` | JSONB | NOT NULL, DEFAULT '[]' | 對話歷史（Claude messages 格式） |
| `tokens_used` | INTEGER | DEFAULT 0 | 累計 Token 使用量 |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |
| `updated_at` | TIMESTAMP | auto | 最後更新時間 |

**messages_history 格式**：
```json
[
  {"role": "user", "content": "爸爸這週血壓如何？"},
  {"role": "assistant", "content": "根據本週紀錄，平均收縮壓 130 mmHg..."}
]
```

**對應功能**: 14.1, 14.5（AI 對話式查詢、多輪對話）

---

### 22. first_aid_documents（急救文件 — RAG）

| 欄位 | 型別 | 約束 | 說明 |
|---|---|---|---|
| `id` | UUID | PK | 文件唯一識別碼 |
| `title` | VARCHAR(300) | NOT NULL | 文件標題 |
| `source` | VARCHAR(200) | NOT NULL | 來源（如「衛福部急救手冊」） |
| `section` | VARCHAR(200) | NULL | 章節 |
| `content` | TEXT | NOT NULL | 文件內容（chunk） |
| `embedding` | VECTOR(1024) | NOT NULL | 文字嵌入向量（pgvector） |
| `created_at` | TIMESTAMP | DEFAULT now() | 建立時間 |

**索引**:
- `INDEX idx_firstaid_embedding ON first_aid_documents USING ivfflat (embedding vector_l2_ops)` — 向量近似搜尋

**對應功能**: 15.3（RAG 急救指引）

---

## 跨模組自動連動整理

| # | 觸發動作 | 寫入目標表 | 寫入內容 | 關聯欄位 |
|---|---|---|---|---|
| 1 | `medication_confirmations` INSERT | `care_logs` INSERT | type=medication 紀錄 | `medication_confirmations.care_log_id` |
| 2 | `todos` UPDATE status=completed | `care_logs` INSERT | type=activity 紀錄 | `todos.care_log_id` |
| 3 | `leaves` UPDATE status=approved | `events` INSERT | type=leave 事件 | `leaves.calendar_event_id` |
| 4 | `medications` INSERT (reminder=true) | `events` INSERT | type=medication 事件 | `events.source_id = medications.id` |
| 5 | `health_data` INSERT (超出閾值) | `health_alerts` INSERT | 異常警示 | 自動觸發 |
| 6 | 上述所有 + 聊天/SOS 等 | `notifications` INSERT | 推播通知 | `notifications.data` 包含來源 ID |

---

## Django Migration 建議順序

```
1. 0001_create_users          # 自訂 User Model（必須最先）
2. 0002_create_families        # 家庭群組
3. 0003_create_chats           # 聊天室 + 成員 + 訊息
4. 0004_create_care_logs       # 照護日誌
5. 0005_create_medications     # 藥物 + 餵藥確認
6. 0006_create_health          # 健康數據 + 閾值 + 警示
7. 0007_create_expenses        # 消費紀錄
8. 0008_create_leaves          # 請假紀錄
9. 0009_create_events_todos    # 行事曆 + 代辦
10. 0010_create_board           # 留言板
11. 0011_create_documents       # 文件管理
12. 0012_create_notifications   # 通知 + 裝置
13. 0013_create_sos             # SOS 紀錄
14. 0014_create_ai              # AI 對話
15. 0015_create_first_aid_rag   # 急救文件（pgvector）
16. 0016_create_indexes         # 所有複合索引
```

---

## 資料表統計

| 統計項目 | 數量 |
|---|---|
| 資料表總數 | **22** |
| 含 JSONB 欄位的表 | 11 |
| 含 FK 外鍵的表 | 20 |
| 含複合索引的表 | 6 |
| 使用 pgvector 的表 | 1 |
| 跨模組自動連動 | 6 條 |
