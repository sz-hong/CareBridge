# CareBridge API Documentation

> Version: v3.3
> Last reviewed: 2026-06-21
> Source of truth: `backend/carebridge_api/urls.py`, `backend/apps/*/urls.py`, `views.py`, `serializers.py`, `models.py`
> Production Base URL: `https://api.carebridge-lab.com/api/v1`
> Local Development Base URL: `http://127.0.0.1:8000/api/v1`
> Production WebSocket Base: `wss://api.carebridge-lab.com`
> Public Storage Base: `https://storage.carebridge-lab.com`
> Runtime: Django REST Framework, SimpleJWT, Channels WebSocket

This document reflects the current backend code and the current public Cloudflare Tunnel setup. Use the production HTTPS base URL for deployed clients and back-office tools; use the local development base URL only when the Django server is running on the same machine.

## Table of Contents

1. [Global Contract](#global-contract)
2. [Authentication](#authentication)
3. [Users and Families](#users-and-families)
4. [Chats and WebSocket](#chats-and-websocket)
5. [Board Requests](#board-requests)
6. [Care Logs](#care-logs)
7. [Medications](#medications)
8. [Expenses](#expenses)
9. [Leaves](#leaves)
10. [Health Data](#health-data)
11. [Calendar Events](#calendar-events)
12. [Todos](#todos)
13. [Documents](#documents)
14. [AI Assistant](#ai-assistant)
15. [SOS](#sos)
16. [Notifications and Devices](#notifications-and-devices)
17. [Enums](#enums)
18. [Admin Dashboard API](#admin-dashboard-api)

## Global Contract

### Authentication

Most endpoints require a JWT access token:

```http
Authorization: Bearer <access_token>
```

Public endpoints:

| Method | Path | Notes |
|---|---|---|
| `GET` | `/health/` | Basic API health check. |
| `POST` | `/auth/register/` | Creates account and returns app auth envelope. |
| `POST` | `/auth/login/` | App login, returns app auth envelope. |
| `POST` | `/auth/token/` | SimpleJWT raw token endpoint. |
| `POST` | `/auth/token/refresh/` | SimpleJWT raw refresh endpoint. |

### API Audience Map

The backend exposes two different API surfaces under the same production base URL:

| Audience | Namespace | Authorization | Data scope |
|---|---|---|---|
| CareBridge app and normal user clients | `/api/v1/auth/*`, `/api/v1/families/*`, `/api/v1/chats/*`, `/api/v1/board/*`, `/api/v1/care-logs/*`, `/api/v1/medications/*`, `/api/v1/expenses/*`, `/api/v1/leaves/*`, `/api/v1/health-data/*`, `/api/v1/events/*`, `/api/v1/todos/*`, `/api/v1/documents/*`, `/api/v1/ai/*`, `/api/v1/sos/*`, `/api/v1/notifications/*` | Normal JWT user | Usually limited to `request.user.family` or `request.user`. |
| Personal web admin dashboard | `/api/v1/admin/*` | Staff JWT user only | Global staff view over allow-listed tables, storage, and logs. |

Important: `/api/v1/health-data/dashboard/` is an app health summary endpoint, not the web admin dashboard API. The web dashboard should use only `/api/v1/admin/*` after login.

### Success Envelope

Most custom API views return:

```json
{
  "success": true,
  "data": {},
  "meta": {}
}
```

`meta` appears only on selected list endpoints. Delete-style commands usually return:

```json
{
  "success": true,
  "data": {}
}
```

SimpleJWT endpoints are exceptions and return raw token JSON, not the `success/data` envelope.

### GET `/health/`

Basic health check.

Authentication: none

Response:

```json
{
  "status": "ok"
}
```

Production example:

```http
GET https://api.carebridge-lab.com/api/v1/health/
```

### Error Envelope

DRF exceptions are normalized by `core.exceptions.custom_exception_handler`:

```json
{
  "success": false,
  "error": {
    "code": "validation_error",
    "message": "field: message"
  }
}
```

Common codes:

| HTTP | Code | Meaning |
|---|---|---|
| `400` | `validation_error`, custom endpoint codes | Invalid request body or query. |
| `401` | `authentication_error` | Missing, expired, or invalid JWT. |
| `403` | `permission_denied` | Authenticated but not allowed. |
| `404` | `not_found` | Resource not found in current scope. |
| `405` | `method_not_allowed` | Route exists but HTTP method is not accepted. |
| `429` | `throttled` | DRF throttling, if configured later. |

Some view code returns custom uppercase codes such as `INVALID_INVITE` and `INVALID_ROLE`.

### Pagination

Default pagination is page-number pagination:

| Query | Type | Default | Notes |
|---|---:|---:|---|
| `page` | integer | `1` | Page number. |
| `page_size` | integer | `20` | Max `100`. |

List response metadata is not perfectly consistent across viewsets. Depending on endpoint, `meta` may contain `count`, `next`, `previous`, `page`, and/or `page_size`.

### Date and Decimal Formats

| Type | Format |
|---|---|
| UUID | String UUID, for example `b5c9b9f4-2a14-4df8-88a5-8fa53fbb4c8a`. |
| Date | ISO date, for example `2026-05-07`. |
| DateTime | ISO 8601 datetime, timezone-aware. |
| Decimal | DRF may serialize decimals as strings. Health values are explicitly returned as numbers. |
| JSON | Arbitrary JSON object or array as accepted by the model field. |

## Authentication

### User Object

```json
{
  "id": "uuid",
  "email": "caregiver@example.com",
  "name": "王小明",
  "role": "caregiver",
  "language": "zh-TW",
  "phone": "0912345678",
  "avatar_url": "https://example.com/avatar.png",
  "family_id": "uuid",
  "family_name": "王家",
  "family_invite_code": "123456",
  "is_primary": false,
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### POST `/auth/register/`

Creates a user account. The current serializer does not accept `role`; role is later assigned by creating or joining a family.

Authentication: none

Request:

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123",
  "name": "王小明",
  "language": "zh-TW",
  "phone": "0912345678"
}
```

Fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `email` | email | yes | Stored lowercase; unique case-insensitively. |
| `password` | string | yes | Minimum length `8`. |
| `name` | string | yes | Max `150`. |
| `language` | enum | no | Default `zh-TW`. |
| `phone` | string | no | Max `20`, blank allowed. |

Response `201`:

```json
{
  "success": true,
  "data": {
    "user": { "id": "uuid", "email": "caregiver@example.com" },
    "tokens": {
      "access": "jwt-access-token",
      "refresh": "jwt-refresh-token"
    }
  }
}
```

### POST `/auth/login/`

Authentication: none

Request:

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "user": { "id": "uuid", "email": "caregiver@example.com" },
    "tokens": {
      "access": "jwt-access-token",
      "refresh": "jwt-refresh-token"
    }
  }
}
```

### POST `/auth/token/`

SimpleJWT raw endpoint. Uses the custom user model where `email` is the username field.

Authentication: none

Request:

```json
{
  "email": "caregiver@example.com",
  "password": "secureP@ss123"
}
```

Response:

```json
{
  "refresh": "jwt-refresh-token",
  "access": "jwt-access-token"
}
```

### POST `/auth/token/refresh/`

Authentication: none

Request:

```json
{
  "refresh": "jwt-refresh-token"
}
```

Response:

```json
{
  "access": "new-jwt-access-token",
  "refresh": "rotated-refresh-token"
}
```

Refresh tokens are configured for 30 days, access tokens for 1 hour, and refresh rotation is enabled.

### GET `/auth/me/`

Returns the authenticated user.

Authentication: required

Response:

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "email": "caregiver@example.com",
    "name": "王小明"
  }
}
```

### PUT/PATCH `/auth/me/`

Updates the authenticated user profile.

Authentication: required

Request fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `name` | string | no | |
| `language` | enum | no | `zh-TW`, `id`, `vi`, `tl`. |
| `phone` | string/null | no | Blank allowed. |
| `avatar_url` | URL/null | no | Blank allowed. |

Response: user object.

### POST `/auth/logout/`

Best-effort refresh token blacklist. Returns success even when blacklist is unavailable or token is invalid.

Authentication: required

Request:

```json
{
  "refresh": "jwt-refresh-token"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "detail": "Successfully logged out."
  }
}
```

### DELETE `/auth/account/`

Deletes the authenticated user account.

Authentication: required

Response:

```json
{
  "success": true,
  "data": {
    "detail": "Account deleted."
  }
}
```

### POST `/auth/join-family/`

Joins a family by invite code and sets the user's role.

Authentication: required

Request:

```json
{
  "invite_code": "123456",
  "role": "caregiver"
}
```

Fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `invite_code` | string | yes | Must be 6 digits. |
| `role` | enum | yes | `caregiver` or `family_member`. |

Response: `{ user, tokens }` in the success envelope.

Side effect: user is added to every existing chat in the joined family.

## Users and Families

Family-scoped endpoints only expose the authenticated user's current family.

### Family Object

```json
{
  "id": "uuid",
  "name": "王家",
  "elder_name": "王奶奶",
  "elder_birth_date": "1940-01-01",
  "invite_code": "123456",
  "created_by": "uuid",
  "created_at": "2026-05-07T10:00:00+08:00",
  "members": []
}
```

### GET `/families/`

Returns the current user's family as a paginated array. If the user has no family, returns an empty array.

Authentication: required

Query: `page`, `page_size`

Response:

```json
{
  "success": true,
  "data": [{ "id": "uuid", "name": "王家" }],
  "meta": {
    "count": 1,
    "next": null,
    "previous": null
  }
}
```

### POST `/families/`

Creates a family and assigns the creator as the primary family member.

Authentication: required

Request:

```json
{
  "name": "王家",
  "elder_name": "王奶奶",
  "elder_birth_date": "1940-01-01"
}
```

Side effects:

| Field | Result |
|---|---|
| `request.user.family` | New family. |
| `request.user.is_primary` | `true`. |
| `request.user.role` | `family_member`. |

Response `201`: family object.

### GET `/families/{family_id}/`

Returns a family object if it is the authenticated user's family.

### PUT/PATCH `/families/{family_id}/`

Updates writable family fields:

| Field | Type |
|---|---|
| `name` | string |
| `elder_name` | string |
| `elder_birth_date` | date/null |

Response: family object.

### DELETE `/families/{family_id}/`

Deletes the family.

Response:

```json
{
  "success": true,
  "data": {
    "detail": "Family deleted."
  }
}
```

### GET `/families/members/`

Returns all users in the current family.

Response:

```json
{
  "success": true,
  "data": [{ "id": "uuid", "name": "王小明" }]
}
```

### POST `/families/{family_id}/join/`

Joins the family identified by path parameter, after validating its invite code.

Request:

```json
{
  "invite_code": "123456"
}
```

Response: family object.

Side effect: user is enrolled into existing family chats.

Implementation note: unlike `/auth/join-family/`, this route does not set `role`.

### DELETE `/families/{family_id}/members/{user_id}/`

Removes a member from the family by clearing `member.family` and `member.is_primary`.

Response:

```json
{
  "success": true,
  "data": {
    "detail": "Member removed."
  }
}
```

## Chats and WebSocket

### Chat Object

```json
{
  "id": "uuid",
  "type": "group",
  "name": "家庭群組",
  "family": "uuid",
  "created_at": "2026-05-07T10:00:00+08:00",
  "members": [
    {
      "id": "uuid",
      "name": "王小明",
      "role": "family_member",
      "avatar_url": null
    }
  ],
  "last_message": {
    "id": "uuid",
    "content": "好的",
    "type": "text",
    "sent_at": "2026-05-07T10:01:00+08:00",
    "sender_id": "uuid"
  },
  "unread_count": 0
}
```

### Message Object

```json
{
  "id": "uuid",
  "chat": "uuid",
  "sender": {
    "id": "uuid",
    "name": "王小明",
    "role": "family_member",
    "avatar_url": null
  },
  "is_me": true,
  "type": "text",
  "message_type": "text",
  "reference_id": null,
  "content": "今天已吃藥",
  "translations": {
    "zh-TW": "今天已吃藥",
    "id": "Obat sudah diminum hari ini"
  },
  "image_url": null,
  "sent_at": "2026-05-07T10:01:00+08:00"
}
```

### GET `/chats/`

Returns chats where the authenticated user is a chat member.

Query: `page`, `page_size`

Response metadata: `count`, `page`, `page_size`.

### POST `/chats/`

Creates a group or direct chat.

Request:

```json
{
  "type": "group",
  "name": "家庭群組",
  "family_id": "uuid",
  "member_ids": ["uuid"]
}
```

Rules:

| Rule | Behavior |
|---|---|
| `family_id` must equal `request.user.family_id` | Otherwise `403 permission_denied`. |
| Every `member_id` must belong to the user's family | Otherwise `400 invalid_members`. |
| Creator | Automatically added even if not in `member_ids`. |

Response `201`: chat object.

### GET `/chats/{chat_id}/`

Returns one chat where the user is a member.

### PUT/PATCH `/chats/{chat_id}/`

Updates chat fields through `ChatSerializer`.

Writable fields in current serializer: `type`, `name`, `family`.

### DELETE `/chats/{chat_id}/`

Deletes the chat.

Response: empty success envelope.

### GET `/chats/{chat_id}/messages/`

Returns paginated messages. The backend fetches the newest page and returns that page in chronological order.

Query: `page`, `page_size`

Response metadata: `count`, `page`, `page_size`.

### POST `/chats/{chat_id}/messages/`

Sends a message.

Text request:

```json
{
  "type": "text",
  "content": "今天已吃藥"
}
```

Image request:

```json
{
  "type": "image",
  "image_url": "https://example.com/photo.jpg"
}
```

Request-card message:

```json
{
  "type": "purchase_request",
  "reference_id": "uuid",
  "content": "採買需求：尿布"
}
```

Field rules:

| `type` | Required fields | Stored fields |
|---|---|---|
| `text` | `content` | `Message.type=text`, `message_type=text`. |
| `image` | `image_url` | `Message.type=image`, `message_type=text`. |
| `purchase_request` | `reference_id`, `content` | `Message.type=text`, `message_type=purchase_request`. |
| `leave_request` | `reference_id`, `content` | `Message.type=text`, `message_type=leave_request`. |

Plain text messages are translated into supported languages when translation is configured.

Response `201`: message object.

### WebSocket `wss://api.carebridge-lab.com/ws/chat/{chat_id}/?token=<access_token>`

Authentication is handled by `JWTAuthMiddleware` from the query string token.

Local development equivalent:

```text
ws://127.0.0.1:8000/ws/chat/{chat_id}/?token=<access_token>
```

Client sends chat message:

```json
{
  "type": "chat.message",
  "message_type": "text",
  "content": "Hello"
}
```

Client sends typing state:

```json
{
  "type": "chat.typing",
  "user_id": "uuid",
  "is_typing": true
}
```

Server message event payload is the serialized Message object, without the HTTP `success/data` wrapper.

Server typing event:

```json
{
  "type": "typing",
  "user_id": "uuid",
  "is_typing": true
}
```

Implementation note: the consumer currently accepts the socket after joining the room group. It does not explicitly reject anonymous users or verify chat membership before `accept()`.

## Board Requests

### BoardRequest Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "requester": { "id": "uuid", "email": "caregiver@example.com" },
  "category": "daily",
  "items": [{ "name": "尿布", "quantity": 1 }],
  "note": "需要補貨",
  "note_translated": null,
  "status": "pending",
  "reply": null,
  "reviewed_by": null,
  "created_at": "2026-05-07T10:00:00+08:00",
  "updated_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/board/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `status` | enum | `pending`, `approved`, `rejected`, `completed`. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`.

### POST `/board/`

Request:

```json
{
  "category": "daily",
  "items": [{ "name": "尿布", "quantity": 1 }],
  "note": "需要補貨"
}
```

Response `201`: board request object.

### GET `/board/{request_id}/`

Returns one board request.

### PUT/PATCH `/board/{request_id}/`

Updates `category`, `items`, and/or `note`. The current implementation treats PUT as partial.

### PATCH `/board/{request_id}/status/`

Updates review status.

Request:

```json
{
  "status": "approved",
  "reply": "今晚會買"
}
```

Allowed statuses: `approved`, `rejected`, `completed`.

Response: board request object.

### DELETE `/board/{request_id}/`

Deletes the request.

## Care Logs

### CareLog Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "recorder": {
    "id": "uuid",
    "name": "王小明"
  },
  "type": "meal",
  "content": {
    "meal": "lunch",
    "amount": "normal"
  },
  "photo_url": null,
  "timestamp": "2026-05-07T12:00:00+08:00",
  "created_at": "2026-05-07T12:01:00+08:00"
}
```

### GET `/care-logs/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `type` | enum | `medication`, `vital`, `meal`, `activity`, `note`. |
| `date` | date or datetime | Filters `timestamp__date`. |
| `date_from` | date | Inclusive. |
| `date_to` | date | Inclusive. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`, `next`, `previous`.

### POST `/care-logs/`

Request:

```json
{
  "type": "meal",
  "content": {
    "meal": "lunch",
    "amount": "normal"
  },
  "photo_url": "https://example.com/photo.jpg",
  "timestamp": "2026-05-07T12:00:00+08:00"
}
```

Response `201`: care log object.

### GET `/care-logs/{log_id}/`

Returns one care log.

### PUT/PATCH `/care-logs/{log_id}/`

Updates `type`, `content`, `photo_url`, and/or `timestamp`.

### DELETE `/care-logs/{log_id}/`

Deletes the care log.

### GET `/care-logs/summary/`

Returns a 7-day summary.

Response:

```json
{
  "success": true,
  "data": {
    "period": {
      "from": "2026-04-30T10:00:00+08:00",
      "to": "2026-05-07T10:00:00+08:00"
    },
    "total_logs_by_type": {
      "meal": 8,
      "medication": 12
    },
    "medication_compliance": {
      "confirmed": 10,
      "total": 12,
      "rate": 0.83
    }
  }
}
```

## Medications

### Medication Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "name": "降血壓藥",
  "name_translated": null,
  "dosage": "5mg",
  "frequency": "daily",
  "times": ["08:00"],
  "instructions": "飯後服用",
  "instructions_translated": null,
  "start_date": "2026-05-01",
  "end_date": null,
  "is_active": true,
  "reminder_enabled": true,
  "created_by": "uuid",
  "created_at": "2026-05-07T10:00:00+08:00",
  "updated_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/medications/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `is_active` | boolean | `true` or `false`. |
| `include_expired` | boolean | Default excludes records where `end_date` is before today. Pass `true` to include. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`, `next`, `previous`.

### POST `/medications/`

Request:

```json
{
  "name": "降血壓藥",
  "dosage": "5mg",
  "frequency": "daily",
  "times": ["08:00"],
  "instructions": "飯後服用",
  "start_date": "2026-05-01",
  "end_date": null,
  "reminder_enabled": true
}
```

Response `201`: medication object.

Side effect: attempts automatic translation for `name` and `instructions`.

### GET `/medications/{medication_id}/`

Returns one medication.

### PUT/PATCH `/medications/{medication_id}/`

Updates create fields: `name`, `dosage`, `frequency`, `times`, `instructions`, `start_date`, `end_date`, `reminder_enabled`.

### DELETE `/medications/{medication_id}/`

Deletes the medication.

### POST `/medications/{medication_id}/confirm/`

Creates a medication confirmation and a linked care log.

Request:

```json
{
  "photo_url": "https://example.com/photo.jpg",
  "scheduled_time": "08:00",
  "note": "已服用"
}
```

Response `201`:

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "medication": "uuid",
    "confirmed_by": {
      "id": "uuid",
      "name": "王小明"
    },
    "photo_url": "https://example.com/photo.jpg",
    "scheduled_time": "08:00",
    "note": "已服用",
    "confirmed_at": "2026-05-07T08:01:00+08:00"
  }
}
```

### GET `/medications/today_confirmations/`

Returns medication confirmations whose `confirmed_at` date is today in server timezone.

## Expenses

### Expense Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "recorder": "uuid",
  "scan_id": null,
  "store_name": "藥局",
  "date": "2026-05-07",
  "items": [
    {
      "name": "尿布",
      "category": "daily",
      "quantity": 1,
      "total": 399
    }
  ],
  "total_amount": "399.00",
  "image_url": "https://presigned-download-url",
  "ocr_confidence": null,
  "status": "completed",
  "created_at": "2026-05-07T10:00:00+08:00",
  "updated_at": "2026-05-07T10:00:00+08:00"
}
```

`image_url` is converted to a short-lived presigned GET URL when possible.

### GET `/expenses/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `status` | enum | `processing`, `completed`, `failed`. |
| `date_from` | date | Inclusive. |
| `date_to` | date | Inclusive. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`, `next`, `previous`.

### POST `/expenses/`

Creates a completed expense record.

Request:

```json
{
  "store_name": "藥局",
  "date": "2026-05-07",
  "items": [
    {
      "name": "尿布",
      "category": "daily",
      "quantity": 1,
      "total": 399
    }
  ],
  "total_amount": "399.00",
  "image_url": "https://example.com/receipt.jpg"
}
```

Response `201`: expense object.

### POST `/expenses/upload-url/`

Creates a presigned S3 PUT URL for receipt upload.

Request:

```json
{
  "content_type": "image/jpeg"
}
```

Supported extension mapping: `image/jpeg`, `image/jpg`, `image/png`, `image/heic`. Unknown types default to `.jpg`.

Response:

```json
{
  "success": true,
  "data": {
    "upload_url": "https://presigned-put-url",
    "image_url": "https://bucket-url/receipts/family-id/file.jpg",
    "key": "receipts/family-id/file.jpg"
  }
}
```

### POST `/expenses/scan/`

Creates a processing expense record from an already uploaded receipt image. The current view does not run OCR directly.

Request:

```json
{
  "image_url": "https://bucket-url/receipts/family-id/file.jpg",
  "date": "2026-05-07"
}
```

Response `202`: expense object with `status=processing`, `items=[]`, `total_amount=0`, and generated `scan_id`.

### GET `/expenses/monthly/`

Returns current-month completed expense total and category breakdown.

Response:

```json
{
  "success": true,
  "data": {
    "monthly_total": 1200.5,
    "category_breakdown": [
      {
        "category": "daily",
        "percentage": 66.5
      }
    ]
  }
}
```

### GET `/expenses/{expense_id}/`

Returns one expense.

### PUT/PATCH `/expenses/{expense_id}/`

Updates `store_name`, `date`, `items`, `total_amount`, and/or `image_url`.

### DELETE `/expenses/{expense_id}/`

Deletes the expense.

## Leaves

### Leave Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "applicant": { "id": "uuid", "email": "caregiver@example.com" },
  "applicant_name": "王小明",
  "type": "personal",
  "start_date": "2026-06-01",
  "end_date": "2026-06-02",
  "days": 2,
  "reason": "家中有事",
  "reason_translated": null,
  "status": "pending",
  "reply": null,
  "reviewed_by": null,
  "reviewed_at": null,
  "calendar_event": null,
  "votes": [],
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/leaves/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `status` | enum | `pending`, `approved`, `rejected`. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`.

### POST `/leaves/`

Request:

```json
{
  "type": "personal",
  "start_date": "2026-06-01",
  "end_date": "2026-06-02",
  "reason": "家中有事"
}
```

Response `201`: leave object.

Side effect: `days` is calculated inclusively as `(end_date - start_date) + 1`.

### GET `/leaves/{leave_id}/`

Returns one leave request.

### PATCH `/leaves/{leave_id}/status/`

Approves or rejects a leave.

Request:

```json
{
  "status": "approved",
  "reply": "可以"
}
```

Rules:

| Status | Side effect |
|---|---|
| `approved` | Creates a linked calendar event if one does not already exist. |
| `rejected` | No calendar event is created. |

Response: leave object.

### POST `/leaves/{leave_id}/vote/`

Upserts the current user's vote.

Request:

```json
{
  "is_available": true
}
```

Auto-resolution rules:

| Votes | Result |
|---|---|
| Any family member votes `is_available=true` | Leave becomes `approved`. |
| All eligible `family_member` users vote `false` | Leave becomes `rejected`. |
| Otherwise | Leave remains `pending`. |

Response: leave object.

### PUT/PATCH/DELETE `/leaves/{leave_id}/`

The router exposes detail update/delete routes from `ModelViewSet`.

Practical contract:

| Method | Current behavior |
|---|---|
| `PUT`/`PATCH` | Uses `LeaveSerializer`, whose fields are read-only. Prefer `/status/` and `/vote/`. |
| `DELETE` | Default DRF destroy deletes the leave. |

## Health Data

### HealthData Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "device_id": "watch-001",
  "type": "heart_rate",
  "value": 78.0,
  "unit": "bpm",
  "recorded_at": "2026-05-07T08:00:00+08:00",
  "created_at": "2026-05-07T08:01:00+08:00"
}
```

### GET `/health-data/`

Family-scoped health data list or aggregation.

Query:

| Query | Type | Notes |
|---|---|---|
| `type` | enum | See health data types. |
| `date_from` | date | Inclusive on `recorded_at__date`. |
| `date_to` | date | Inclusive on `recorded_at__date`. |
| `aggregation` | enum | `raw`, `hourly`, `daily`. Omit for raw. |

Raw response returns up to 200 newest rows in model ordering.

Aggregation response:

```json
{
  "success": true,
  "data": [
    {
      "type": "heart_rate",
      "period": "2026-05-07T08:00:00+08:00",
      "avg_value": 78.5
    }
  ]
}
```

### POST `/health-data/sync/`

Batch syncs health data. Duplicate key is `(family, type, recorded_at)`.

Request:

```json
{
  "data": [
    {
      "type": "heart_rate",
      "value": "78.00",
      "unit": "bpm",
      "recorded_at": "2026-05-07T08:00:00+08:00",
      "device_id": "watch-001"
    }
  ]
}
```

Response `201`:

```json
{
  "success": true,
  "data": {
    "synced": 1,
    "duplicates": 0,
    "alerts": []
  }
}
```

Side effect: new heart-rate and blood-oxygen points are checked against alert thresholds.

### GET `/health-data/dashboard/`

Returns the latest data point for each health type.

Response:

```json
{
  "success": true,
  "data": {
    "heart_rate": { "value": 78.0, "unit": "bpm" },
    "blood_oxygen": { "value": 97.0, "unit": "%" }
  }
}
```

### GET `/health-data/alerts/`

Returns the latest 100 family alerts.

### PUT `/health-data/alerts/{alert_id}/acknowledge/`

Marks one alert as acknowledged by the current user.

Response: health alert object.

### GET `/health-data/thresholds/`

Returns the family thresholds, creating default thresholds if missing.

Default values:

```json
{
  "heart_rate_high": 100,
  "heart_rate_low": 50,
  "blood_oxygen_low": "93.0"
}
```

### PUT `/health-data/thresholds/`

Updates thresholds.

Request:

```json
{
  "heart_rate_high": 105,
  "heart_rate_low": 48,
  "blood_oxygen_low": "92.5"
}
```

Response: threshold object.

### GET `/health-data/weekly-steps/`

Returns a 7-element integer array, oldest day to newest day.

```json
{
  "success": true,
  "data": [3000, 4200, 0, 5100, 6200, 7000, 4500]
}
```

## Calendar Events

### Event Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "title": "回診",
  "title_translated": null,
  "start_time": "2026-05-10T09:00:00+08:00",
  "end_time": "2026-05-10T10:00:00+08:00",
  "location": "台大醫院",
  "type": "medical",
  "reminder_minutes": 60,
  "note": "帶健保卡",
  "source": "manual",
  "source_id": null,
  "created_by": { "id": "uuid", "email": "caregiver@example.com" },
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/events/`

Family-scoped list. This endpoint disables pagination.

Query:

| Query | Type | Notes |
|---|---|---|
| `type` | enum | `medical`, `medication`, `rehab`, `leave`, `personal`, `other`. |
| `start_after` | datetime | Inclusive. |
| `start_before` | datetime | Inclusive. |

### POST `/events/`

Request:

```json
{
  "title": "回診",
  "start_time": "2026-05-10T09:00:00+08:00",
  "end_time": "2026-05-10T10:00:00+08:00",
  "location": "台大醫院",
  "type": "medical",
  "reminder_minutes": 60,
  "note": "帶健保卡"
}
```

Response `201`: event object.

### POST `/events/batch/`

Creates multiple events.

Request can be either a raw array:

```json
[
  {
    "title": "回診",
    "start_time": "2026-05-10T09:00:00+08:00",
    "type": "medical"
  }
]
```

Or wrapped:

```json
{
  "events": [
    {
      "title": "回診",
      "start_time": "2026-05-10T09:00:00+08:00",
      "type": "medical"
    }
  ]
}
```

Response `201`: event object array.

### GET `/events/{event_id}/`

Returns one event.

### PUT/PATCH `/events/{event_id}/`

Updates create fields. Current implementation treats update as partial.

### DELETE `/events/{event_id}/`

Deletes the event.

## Todos

### Todo Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "title": "量血壓",
  "title_translated": null,
  "assignee": { "id": "uuid", "email": "caregiver@example.com" },
  "priority": "medium",
  "status": "pending",
  "due_date": "2026-05-08",
  "completed_at": null,
  "care_log": null,
  "created_by": { "id": "uuid", "email": "creator@example.com" },
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/todos/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `status` | enum | `pending`, `completed`. |
| `assignee` | UUID | Filters by assigned user id. |
| `priority` | enum | `high`, `medium`, `low`. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`.

### POST `/todos/`

Request:

```json
{
  "title": "量血壓",
  "assignee_id": "uuid",
  "priority": "medium",
  "due_date": "2026-05-08"
}
```

Response `201`: todo object.

### GET `/todos/{todo_id}/`

Returns one todo.

### PUT/PATCH `/todos/{todo_id}/`

Updates simple fields:

| Field | Type |
|---|---|
| `title` | string |
| `priority` | enum |
| `due_date` | date/null |
| `status` | enum |

Side effect: if status changes from not completed to `completed`, the backend creates an `activity` care log and links it to `todo.care_log`.

### DELETE `/todos/{todo_id}/`

Deletes the todo.

## Documents

### Document Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "title": "保險文件",
  "category": "insurance",
  "file_url": "https://example.com/file.pdf",
  "file_size": 102400,
  "mime_type": "application/pdf",
  "uploaded_by": { "id": "uuid", "email": "user@example.com" },
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/documents/`

Family-scoped list.

Query:

| Query | Type | Notes |
|---|---|---|
| `category` | enum | `insurance`, `medical`, `id_document`, `contract`, `other`. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`.

### POST `/documents/`

Registers a document record. There is currently no document upload-url endpoint.

Request:

```json
{
  "title": "保險文件",
  "category": "insurance",
  "file_url": "https://example.com/file.pdf",
  "file_size": 102400,
  "mime_type": "application/pdf"
}
```

Response `201`: document object.

### GET `/documents/{document_id}/`

Returns one document.

### DELETE `/documents/{document_id}/`

Deletes the document record.

### PUT/PATCH `/documents/{document_id}/`

The router exposes update routes, but the default update uses `DocumentSerializer`, whose fields are read-only. Do not rely on document update until a writable update serializer is added.

## AI Assistant

All AI endpoints require `OPENAI_API_KEY` and use `OPENAI_MODEL` from Django settings.

### POST `/ai/chat/`

Conversational AI with tool calling. Supports non-streaming JSON and SSE streaming.

Query:

| Query | Type | Notes |
|---|---|---|
| `stream` | boolean | `true`, `1`, `yes`, `false`, `0`, `no`. If omitted, `Accept: text/event-stream` also enables streaming. |

Request:

```json
{
  "message": "請分析最近一週的健康狀況",
  "conversation_id": "uuid"
}
```

`conversation_id` is optional. If omitted, a new conversation is created.

Non-streaming response:

```json
{
  "success": true,
  "data": {
    "conversation_id": "uuid",
    "reply": "分析內容...",
    "tokens_used": 1234
  }
}
```

SSE events:

```text
data: {"type":"tool_call","tool":"query_health_data"}

data: {"type":"content","text":"分析"}

data: {"type":"done","conversation_id":"uuid"}
```

Available AI tools:

| Tool | Purpose |
|---|---|
| `query_health_data` | Recent vitals by type and days. |
| `query_care_logs` | Recent care logs by type and days. |
| `query_medications` | Current medications. |
| `query_expenses` | Expenses and totals. |
| `query_events` | Upcoming events. |

### POST `/ai/care-analysis/`

Generates a care analysis report.

Request:

```json
{
  "days": 7
}
```

Fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `days` | integer | no | Default `7`, min `1`, max `90`. |

Response:

```json
{
  "success": true,
  "data": {
    "analysis": "report text",
    "period_days": 7,
    "tokens_used": 1234
  }
}
```

### POST `/ai/handover-report/`

Generates a bilingual handover report.

Request:

```json
{
  "date": "2026-05-07"
}
```

`date` is optional and defaults to today.

Response:

```json
{
  "success": true,
  "data": {
    "report": "handover report text",
    "date": "2026-05-07",
    "tokens_used": 1234
  }
}
```

### POST `/ai/subsidy-form/`

Generates suggested fields for a Taiwan subsidy form.

Request:

```json
{
  "form_type": "long_term_care"
}
```

Allowed `form_type`: `long_term_care`, `disability`, `respite_care`.

Response:

```json
{
  "success": true,
  "data": {
    "form_type": "long_term_care",
    "form_fields": {},
    "tokens_used": 1234
  }
}
```

### POST `/ai/first-aid/`

First-aid RAG query. Uses embedded `FirstAidDocument` records when available, otherwise falls back to direct model guidance.

Request:

```json
{
  "query": "老人跌倒後該怎麼處理？"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "answer": "急救步驟...",
    "sources": [
      {
        "title": "Fall response",
        "source": "manual"
      }
    ],
    "tokens_used": 1234
  }
}
```

Implementation caveat: several AI report views currently reference fields that do not exist in models (`Medication.time_slots`, `Expense.amount`) or aggregate inappropriate fields. These endpoints should be smoke-tested and fixed before being exposed in a back-office production UI.

## SOS

### SOSRecord Object

```json
{
  "id": "uuid",
  "family": "uuid",
  "triggered_by": { "id": "uuid", "email": "user@example.com" },
  "location": {
    "lat": 25.033,
    "lng": 121.565
  },
  "situation": "跌倒",
  "auto_call_119": true,
  "notified_members": ["uuid"],
  "status": "triggered",
  "triggered_at": "2026-05-07T10:00:00+08:00",
  "resolved_at": null
}
```

### POST `/sos/trigger/`

Creates an SOS record and broadcasts notifications to family members except the triggering user.

Request:

```json
{
  "location": {
    "lat": 25.033,
    "lng": 121.565
  },
  "situation": "跌倒"
}
```

Response `201`:

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "status": "triggered",
    "notified_count": 3
  }
}
```

### GET `/sos/history/`

Returns all SOS records for the current family.

### PATCH `/sos/{sos_id}/resolve/`

Marks an SOS as resolved and broadcasts a resolved notification.

Request body: none required.

Response: SOS record object.

Errors:

| Code | HTTP | Notes |
|---|---:|---|
| `not_found` | `404` | SOS record is not in current family. |
| `sos_already_resolved` | `400` | Already resolved. |

## Notifications and Devices

### Notification Object

```json
{
  "id": "uuid",
  "user": "uuid",
  "type": "chat_message",
  "title": "New message",
  "title_translated": null,
  "body": "Preview",
  "body_translated": null,
  "data": {
    "chat_id": "uuid"
  },
  "is_read": false,
  "read_at": null,
  "created_at": "2026-05-07T10:00:00+08:00"
}
```

### Device Object

```json
{
  "id": "uuid",
  "user": "uuid",
  "device_token": "apns-device-token",
  "platform": "ios",
  "device_name": "iPhone",
  "is_active": true,
  "created_at": "2026-05-07T10:00:00+08:00",
  "updated_at": "2026-05-07T10:00:00+08:00"
}
```

### GET `/notifications/`

Returns notifications for the authenticated user.

Query:

| Query | Type | Notes |
|---|---|---|
| `is_read` | boolean | `true` or `false`. |
| `page`, `page_size` | integer | Pagination. |

Response metadata: `count`.

### GET `/notifications/{notification_id}/`

Returns one notification owned by the authenticated user.

### PUT `/notifications/{notification_id}/read/`

Marks one notification as read.

Response: notification object.

### PUT `/notifications/read-all/`

Marks all unread notifications for the current user as read.

Response:

```json
{
  "success": true,
  "data": {
    "updated_count": 5
  }
}
```

### POST `/notifications/device/`

Registers or updates a device token.

Request:

```json
{
  "device_token": "apns-device-token",
  "platform": "ios",
  "device_name": "iPhone"
}
```

Allowed `platform`: `ios`, `watchos`.

Response:

| Case | HTTP |
|---|---:|
| New device | `201` |
| Existing `(user, device_token)` updated | `200` |

Response data: device object.

### Router-exposed Notification CRUD

The router exposes `POST`, `PUT`, `PATCH`, and `DELETE` on `/notifications/` and `/notifications/{id}/` because `NotificationViewSet` inherits `ModelViewSet`.

Practical contract:

| Method | Current behavior |
|---|---|
| `POST /notifications/` | Not suitable for clients; serializer fields are read-only and model required fields are not supplied. |
| `PUT/PATCH /notifications/{id}/` | Read-only serializer means updates are not a useful public contract. |
| `DELETE /notifications/{id}/` | Default DRF delete is exposed and can delete a user's notification. |

## Enums

### User

| Enum | Values |
|---|---|
| `role` | `caregiver`, `family_member`, `elder` |
| `language` | `zh-TW`, `id`, `vi`, `tl` |

### Chat

| Enum | Values |
|---|---|
| `Chat.type` | `group`, `direct` |
| `Message.type` | `text`, `image` |
| `Message.message_type` | `text`, `purchase_request`, `leave_request` |

### Care and Operations

| Enum | Values |
|---|---|
| `BoardRequest.category` | `food`, `daily`, `medical`, `other` |
| `BoardRequest.status` | `pending`, `approved`, `rejected`, `completed` |
| `CareLog.type` | `medication`, `vital`, `meal`, `activity`, `note` |
| `Medication.frequency` | `daily`, `twice_daily`, `thrice_daily`, `weekly`, `as_needed` |
| `Expense.status` | `processing`, `completed`, `failed` |
| `Leave.type` | `personal`, `sick`, `emergency` |
| `Leave.status` | `pending`, `approved`, `rejected` |
| `Event.type` | `medical`, `medication`, `rehab`, `leave`, `personal`, `other` |
| `Event.source` | `manual`, `medication`, `leave` |
| `Todo.priority` | `high`, `medium`, `low` |
| `Todo.status` | `pending`, `completed` |
| `Document.category` | `insurance`, `medical`, `id_document`, `contract`, `other` |

### Health

| Enum | Values |
|---|---|
| `HealthData.type` | `heart_rate`, `blood_oxygen`, `step_count`, `active_energy`, `blood_pressure_systolic`, `blood_pressure_diastolic` |
| `HealthData.unit` | `bpm`, `%`, `steps`, `kcal`, `mmHg` |
| `HealthAlert.severity` | `warning`, `critical` |

### SOS and Notifications

| Enum | Values |
|---|---|
| `SOSRecord.status` | `triggered`, `resolved` |
| `Device.platform` | `ios`, `watchos` |
| `Notification.type` | `health_alert`, `medication_reminder`, `medication_confirmed`, `leave_request`, `leave_status`, `board_request`, `board_approved`, `expense_scanned`, `sos`, `sos_resolved`, `event_reminder`, `todo_assigned`, `chat_message` |

## Admin Dashboard API

### Current API Scope

Most app resource endpoints remain family-scoped through `request.user.family`. The dedicated admin API below is the staff-only exception and is intended for the personal web dashboard.

Production admin clients should use:

```http
https://api.carebridge-lab.com/api/v1/admin/
```

The production dashboard origin `https://shao-zhen.com` is allowed by CORS. Local dashboard development origins `http://127.0.0.1:4173` and `http://localhost:4321` are also allowed. Bearer tokens are used in the `Authorization` header; `CORS_ALLOW_CREDENTIALS` is intentionally `false`.

### Existing Django Admin Surface

Django admin is mounted at:

```http
https://api.carebridge-lab.com/admin/
```

It uses Django session authentication, not the API JWT envelope. The web dashboard should use `/api/v1/admin/*` instead of scraping or depending on `/admin/`.

### Staff Admin API Rules

All `/api/v1/admin/*` endpoints require:

```http
Authorization: Bearer <staff_access_token>
```

The authenticated user must be active and staff: `is_authenticated`, `is_active`, and `is_staff`. Anonymous requests return `401`; authenticated non-staff users return `403`.

Current staff API methods:

| Method | Supported endpoints |
|---|---|
| `GET` | Overview, activity, schema, table list, lookup, record detail, storage list, presign, request logs, raw logs. |
| `POST` | Table create, file upload. |
| `DELETE` | Record soft delete. |
| `OPTIONS` | CORS preflight. |

Allow-listed table names:

`users`, `families`, `care_logs`, `board_requests`, `todos`, `events`, `health_data`, `health_alerts`, `health_thresholds`, `expenses`, `documents`

Writable table names:

`care_logs`, `board_requests`, `todos`, `events`, `health_data`, `health_alerts`, `health_thresholds`, `expenses`, `documents`

Read-only table names:

`users`, `families`

File upload table names:

`care_logs`, `expenses`, `documents`

Sensitive fields such as `password`, token fields, secret fields, credentials, private keys, and APNs secrets are excluded from list/detail/lookup serialization.

### Admin Endpoint Index

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/admin/overview/` | Global KPIs, per-table counts, and operational alerts. |
| `GET` | `/admin/activity/` | Recent global activity derived from model timestamps. |
| `GET` | `/admin/tables/{table}/schema/` | Form schema for creating records and showing table capabilities. |
| `GET` | `/admin/tables/{table}/` | Global list view for one allow-listed table. |
| `POST` | `/admin/tables/{table}/` | Create one record in a writable table. |
| `GET` | `/admin/lookups/users/` | Search users for relation fields. |
| `GET` | `/admin/lookups/families/` | Search families for relation fields. |
| `GET` | `/admin/records/{table}/{id}/` | Read one record plus related file references. |
| `DELETE` | `/admin/records/{table}/{id}/` | Soft-delete one writable record through audit tombstone filtering. |
| `GET` | `/admin/storage/objects/` | List configured bucket objects and identify orphaned files. |
| `GET` | `/admin/files/presign/` | Return a short-lived preview or download URL for one object. |
| `POST` | `/admin/files/upload/` | Upload a file to the configured bucket using backend credentials. |
| `GET` | `/admin/request-logs/` | Structured request monitor for all `/api/v1/*` requests. |
| `GET` | `/admin/logs/` | Tail allow-listed raw log files. |

### GET `/admin/overview/`

Returns global KPIs, table counts, records created/updated in the last 24 hours, and operational alerts.

Response shape:

```json
{
  "success": true,
  "data": {
    "kpis": [{ "label": "Users", "value": 10, "delta_24h": 1 }],
    "tables": [
      {
        "table": "users",
        "count": 10,
        "created_24h": 1,
        "updated_24h": 1
      }
    ],
    "alerts": [
      { "severity": "critical", "title": "Unacknowledged critical health alerts", "count": 2 }
    ]
  }
}
```

Current alerts include unacknowledged critical health alerts, missing storage bucket configuration, missing storage credentials, and storage listing failure when storage credentials are configured.

### GET `/admin/activity/`

Derives recent global activity from allow-listed model timestamps. It does not use a dedicated audit table, so `actor` is `null` when the model has no actor field.

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `limit` | integer | `12` | `100` | Number of activity items. |
| `since` | datetime | none | n/a | Include activity at or after this timestamp. |
| `cursor` | datetime | none | n/a | Include activity before this timestamp. |

Response shape:

```json
{
  "success": true,
  "data": {
    "results": [
      {
        "id": "users:uuid:created:2026-05-09T10:00:00+08:00",
        "table": "users",
        "record_id": "uuid",
        "action": "created",
        "actor": null,
        "created_at": "2026-05-09T10:00:00+08:00"
      }
    ],
    "next_cursor": null
  }
}
```

### GET `/admin/tables/{table}/schema/`

Returns backend-driven form metadata for one table. The dashboard should call this endpoint before rendering a create form.

Unknown table names return `404`.

Response shape:

```json
{
  "success": true,
  "data": {
    "table": "todos",
    "create_allowed": true,
    "delete_allowed": true,
    "fields": [
      {
        "name": "family_id",
        "label": "Family",
        "type": "relation",
        "control": "relation",
        "required": true,
        "readonly": false,
        "default": null,
        "choices": [],
        "relation": {
          "resource": "families",
          "lookup_url": "/api/v1/admin/lookups/families/"
        }
      },
      {
        "name": "title",
        "label": "Title",
        "type": "string",
        "control": "text",
        "required": true,
        "readonly": false,
        "default": null,
        "choices": []
      }
    ]
  }
}
```

Field schema:

| Field | Type | Notes |
|---|---|---|
| `name` | string | Body key to submit. Foreign keys use `{field}_id`, for example `family_id`. |
| `label` | string | Human label derived from the model field verbose name. |
| `type` | string | `string`, `integer`, `decimal`, `boolean`, `date`, `datetime`, `json`, `choice`, or `relation`. |
| `control` | string | Suggested control: `text`, `textarea`, `email`, `url`, `number`, `checkbox`, `date`, `datetime`, `json`, `select`, `relation`, or `uuid`. |
| `required` | boolean | True when model field has no default and is not blank/null. |
| `readonly` | boolean | True for read-only table schemas. |
| `default` | any | Static model default when available. Callable defaults return `null`. |
| `choices` | array | Enum choices as `{ value, label }`. |
| `relation` | object | Present for user/family foreign keys that can use lookup APIs. |

For `users` and `families`, `create_allowed=false`, `delete_allowed=false`, and fields are returned as read-only.

### GET `/admin/lookups/{resource}/`

Searches relation options for admin forms. Supported resources are `users` and `families`.

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `search` | string | none | n/a | Searches allow-listed fields. |
| `page` | integer | `1` | n/a | Page number. |
| `page_size` | integer | `20` | `100` | Values above `100` are capped. |

Response shape:

```json
{
  "success": true,
  "data": {
    "results": [
      {
        "id": "uuid",
        "label": "Jane Caregiver (jane@example.com)",
        "raw": {
          "id": "uuid",
          "email": "jane@example.com",
          "name": "Jane Caregiver"
        }
      }
    ],
    "count": 1,
    "next": null,
    "previous": null,
    "page": 1,
    "page_size": 20
  }
}
```

### GET `/admin/tables/{table}/`

Returns a global table view for allow-listed tables. Unknown tables return `404`.

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `page` | integer | `1` | n/a | Page number. |
| `page_size` | integer | `20` | `100` | Values above `100` are capped. |
| `search` | string | none | n/a | Searches only per-table allow-listed fields. |
| `date_from` | date/datetime | none | n/a | Lower timestamp/date bound. |
| `date_to` | date/datetime | none | n/a | Upper timestamp/date bound. |

Response shape:

```json
{
  "success": true,
  "data": {
    "results": [],
    "count": 0,
    "next": null,
    "previous": null,
    "page": 1,
    "page_size": 20
  }
}
```

### POST `/admin/tables/{table}/`

Creates one record in a writable table. Unknown tables return `404`. Read-only tables return `403 mutation_not_allowed`.

Request body must be JSON object. The accepted keys are the model's editable fields; foreign keys may be submitted as either `{field}_id` or `{field}`. Unknown keys produce field-level validation errors.

Example request:

```json
{
  "family_id": "uuid",
  "title": "Follow up medication refill",
  "priority": "medium",
  "status": "pending",
  "due_date": "2026-05-12",
  "assignee_id": "uuid",
  "created_by_id": "uuid"
}
```

Response `201`:

```json
{
  "success": true,
  "data": {
    "record": {
      "id": "uuid",
      "family_id": "uuid",
      "title": "Follow up medication refill"
    },
    "raw": {
      "id": "uuid",
      "family_id": "uuid",
      "title": "Follow up medication refill"
    }
  }
}
```

Validation error shape:

```json
{
  "success": false,
  "error": {
    "code": "validation_error",
    "message": "Invalid request body.",
    "fields": {
      "family_id": ["This field is required."],
      "unexpected": ["Unknown field."]
    }
  }
}
```

Successful creates are recorded in `admin_mutation_audit_log`.

### GET `/admin/records/{table}/{id}/`

Returns one allow-listed record, its related storage object references, and a raw copy of the serialized record. Unknown tables or IDs return `404`.

Response shape:

```json
{
  "success": true,
  "data": {
    "record": { "id": "uuid" },
    "related_files": [
      {
        "bucket": "carebridge-storage",
        "object_key": "receipts/family/receipt.jpg",
        "linked_table": "expenses",
        "linked_record_id": "uuid",
        "orphan": false
      }
    ],
    "raw": { "id": "uuid" }
  }
}
```

Related files are parsed from allow-listed URL fields such as `file_url`, `image_url`, `photo_url`, and `avatar_url`.

### DELETE `/admin/records/{table}/{id}/`

Soft-deletes one record from a writable admin table. The underlying domain row is not physically deleted. Instead, the delete is written to `admin_mutation_audit_log`, and admin list/detail/activity/storage helpers filter those tombstoned records out.

Read-only tables return `403 mutation_not_allowed`. Unknown tables or IDs return `404`.

Response:

```json
{
  "success": true,
  "data": {
    "table": "todos",
    "id": "uuid",
    "deleted": true,
    "delete_mode": "soft",
    "deleted_at": "2026-05-09T10:00:00+08:00"
  }
}
```

### GET `/admin/storage/objects/`

Lists objects from the configured `AWS_STORAGE_BUCKET_NAME` using backend credentials. Clients cannot provide arbitrary credentials. The optional `bucket` query must be omitted or exactly match the configured bucket.

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `bucket` | string | configured bucket | n/a | Must equal `AWS_STORAGE_BUCKET_NAME` if present. |
| `prefix` | string | empty | n/a | Rejects `..` and backslashes. |
| `page` | integer | `1` | n/a | Page number over returned object list. |
| `page_size` | integer | `20` | `100` | Values above `100` are capped. |
| `orphan` | boolean | none | n/a | Filter to orphan or linked objects. |

Response shape:

```json
{
  "success": true,
  "data": {
    "results": [
      {
        "bucket": "carebridge-storage",
        "object_key": "docs/report.pdf",
        "size": 100,
        "last_modified": "2026-05-09T10:00:00+08:00",
        "content_type": null,
        "linked_table": "documents",
        "linked_record_id": "uuid",
        "orphan": false
      }
    ],
    "count": 1,
    "page": 1,
    "page_size": 20
  }
}
```

### GET `/admin/files/presign/`

Returns a short-lived signed URL for previewing or downloading an object from the configured bucket. The backend first verifies the object with `head_object`.

Query params:

| Query | Type | Required | Notes |
|---|---|---:|---|
| `bucket` | string | no | Must be omitted or equal `AWS_STORAGE_BUCKET_NAME`. |
| `object_key` | string | yes | Rejects empty values, backslashes, and path traversal. |
| `mode` | enum | yes | `preview` or `download`. |

Response:

```json
{
  "success": true,
  "data": {
    "url": "https://signed-url.example",
    "expires_in": 300,
    "content_type": "application/pdf",
    "filename": "report.pdf",
    "size": 12345,
    "disposition": "inline"
  }
}
```

Errors:

| Code | HTTP | Notes |
|---|---:|---|
| `invalid_bucket` | `400` | Bucket omitted when settings are missing, or bucket does not match. |
| `invalid_object_key` | `400` | Unsafe object key. |
| `invalid_mode` | `400` | Mode is not `preview` or `download`. |
| `not_found` | `404` | Object is not found by storage backend. |
| `presign_error` | `502` | Storage client failed to generate signed URL. |

Successful presigns are recorded in `admin_mutation_audit_log` with action `presign_preview` or `presign_download`.

### POST `/admin/files/upload/`

Uploads a file to the configured bucket using backend storage credentials. This endpoint accepts `multipart/form-data`, not JSON.

Allowed content types:

`application/pdf`, `image/jpeg`, `image/png`, `image/webp`, `text/plain`

Maximum file size: `10485760` bytes.

Form fields:

| Field | Type | Required | Notes |
|---|---|---:|---|
| `bucket` | string | no | Must be omitted or equal `AWS_STORAGE_BUCKET_NAME`. |
| `table` | string | yes | Must be `care_logs`, `expenses`, or `documents`. |
| `file` | file | yes | Uploaded file. |
| `family_id` | string | no | Used in object key path; defaults to `unscoped`. Unsafe path segments are rejected. |
| `purpose` | string | no | Used in object key path; defaults to `upload`. Unsafe path segments are rejected. |

Generated object key:

```text
admin/{table}/{family_id}/{purpose}/{uuid}/{filename}
```

Response `201`:

```json
{
  "success": true,
  "data": {
    "bucket": "carebridge-storage",
    "object_key": "admin/documents/family-uuid/upload/uuid/report.pdf",
    "filename": "report.pdf",
    "content_type": "application/pdf",
    "size": 12345,
    "url": "https://storage.carebridge-lab.com/admin/documents/family-uuid/upload/uuid/report.pdf"
  }
}
```

Successful uploads are recorded in `admin_mutation_audit_log` with action `upload`.

### GET `/admin/request-logs/`

Returns structured request logs for all `/api/v1/*` requests. This is the primary dashboard API monitor. It records request metadata only, not request bodies, response bodies, passwords, JWTs, MinIO secrets, or raw Authorization headers.

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `page` | integer | `1` | n/a | Page number. |
| `page_size` | integer | `20` | `100` | Values above `100` are capped. |
| `search` | string | none | n/a | Searches path, query, user email, request id, error code, and error message. |
| `method` | string | none | n/a | `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, etc. |
| `status_class` | string | none | n/a | Must match `1xx`, `2xx`, `3xx`, `4xx`, or `5xx`. |
| `status_code` | integer | none | n/a | Exact HTTP status. |
| `date_from` | date/datetime | none | n/a | Lower created_at bound. |
| `date_to` | date/datetime | none | n/a | Upper created_at bound. |
| `path` | string | none | n/a | Case-insensitive path contains filter. |

Response shape:

```json
{
  "success": true,
  "data": {
    "results": [
      {
        "id": "uuid",
        "request_id": "req-123",
        "method": "POST",
        "path": "/api/v1/auth/login/",
        "query": "",
        "status_code": 200,
        "status_class": "2xx",
        "success": true,
        "duration_ms": 42,
        "user_id": "uuid",
        "user_email": "staff@example.com",
        "is_staff": true,
        "ip": "203.0.113.10",
        "user_agent": "Mozilla/5.0",
        "error_code": null,
        "error_message": null,
        "created_at": "2026-05-09T10:00:00+08:00"
      }
    ],
    "count": 1,
    "next": null,
    "previous": null,
    "page": 1,
    "page_size": 20
  }
}
```

Retention: request logs are intended to be cleaned after 14 days with:

```bash
python manage.py cleanup_admin_request_logs --days 14
```

### GET `/admin/logs/`

Reads only allow-listed raw log streams. It does not accept filesystem paths. This endpoint is a supporting raw file tail; the dashboard request monitor should prefer `/admin/request-logs/`.

Streams:

| Stream | File |
|---|---|
| `runtime` | `backend/logs/runtime.log` |
| `api-errors` | `backend/logs/api-errors.log` |

Query params:

| Query | Type | Default | Max | Notes |
|---|---:|---:|---:|---|
| `stream` | string | `runtime` | n/a | Must be `runtime` or `api-errors`. |
| `lines` | integer | `100` | `500` | Values above `500` are capped. |

Response shape:

```json
{
  "success": true,
  "data": {
    "stream": "runtime",
    "lines": [
      {
        "timestamp": "2026-05-09 10:00:00.000",
        "level": "INFO",
        "message": "Runtime started",
        "request_id": null
      }
    ],
    "next_cursor": null
  }
}
```

### Dashboard Frontend Flow

Recommended login and data flow:

1. `POST /auth/login/` with staff email/password.
2. Store `data.tokens.access` in memory or secure client storage according to the frontend security policy.
3. Verify staff authorization by calling `GET /admin/overview/`.
4. Render table list with `GET /admin/tables/{table}/`.
5. Render create forms from `GET /admin/tables/{table}/schema/`.
6. For relation fields, query `/admin/lookups/users/` or `/admin/lookups/families/`.
7. Submit form JSON to `POST /admin/tables/{table}/`.
8. Delete records through `DELETE /admin/records/{table}/{id}/`.
9. Monitor API traffic through `GET /admin/request-logs/`.

TypeScript fetch helper:

```ts
const API_BASE = "https://api.carebridge-lab.com/api/v1";

async function apiFetch<T>(
  path: string,
  token: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Bearer ${token}`);
  if (!(init.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers,
  });
  const payload = await response.json();
  if (!response.ok || payload.success === false) {
    throw payload.error ?? new Error(`HTTP ${response.status}`);
  }
  return payload.data as T;
}
```

### Known Implementation Caveats

These are not documentation guesses; they come from the current code:

| Area | Caveat |
|---|---|
| AI reports | Some queries reference model fields that do not exist, such as `time_slots` and `amount`. |
| Notification CRUD | Router exposes create/update/delete because of `ModelViewSet`, but only list/retrieve/read/read-all/device registration are intentional public contracts. |
| Document update | Router exposes update, but serializer is read-only outside create. |
| Leave update | Router exposes detail update, but the main mutation paths are `/status/` and `/vote/`. |
| Permissions | Many review/delete actions only require authentication and family scope; no `is_primary` or role checks are enforced in code. |
| WebSocket | Chat socket accepts before explicit membership validation. |
