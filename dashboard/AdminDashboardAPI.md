# CareBridge Admin Dashboard API

## Runtime and Cloudflare

Dashboard container port: `3000`.

Cloudflare Public Hostname:

| Hostname | Service |
| --- | --- |
| `dashboard.carebridge-lab.com` | `http://dashboard:3000` |

The dashboard Nginx container serves the React build and proxies `/api/v1/*` to `http://web:8000`. In production the browser calls same-origin paths such as `/api/v1/admin/tables/`, so CORS is only needed if a development build calls `https://api.carebridge-lab.com` directly.

## Authentication

Use staff JWT authentication.

1. `POST /api/v1/auth/login/`
2. Store `data.tokens.access` for dashboard API requests.
3. Send `Authorization: Bearer <access_token>` on every `/api/v1/admin/*` call.
4. Verify staff access with `GET /api/v1/admin/overview/`.

Anonymous requests return `401`; authenticated non-staff users return `403`.

## Admin Table Capabilities

`GET /api/v1/admin/tables/` returns dashboard table metadata:

```json
{
  "results": [
    {
      "table": "todos",
      "display_name": "Todos",
      "category": "Care Operations",
      "model": "todo.Todo",
      "capabilities": { "list": true, "detail": true, "schema": true, "create": true, "update": true, "delete": true },
      "endpoints": {
        "list": "/api/v1/admin/tables/todos/",
        "schema": "/api/v1/admin/tables/todos/schema/",
        "detail": "/api/v1/admin/records/todos/{id}/"
      }
    }
  ],
  "count": 1
}
```

Read-only tables: `users`, `families`.

Mutable product tables: `care_logs`, `board_requests`, `todos`, `events`, `health_data`, `health_alerts`, `health_thresholds`, `medications`, `medication_confirmations`, `expenses`, `documents`, `leaves`, `leave_votes`, `chats`, `chat_members`, `messages`, `notifications`, `devices`, `sos_records`, `ai_conversations`, `first_aid_documents`.

Sensitive fields such as passwords, tokens, credentials, private keys, APNs fields, embeddings, and raw AI message history are excluded from dashboard serialization.

## CRUD Endpoints

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/api/v1/admin/tables/{table}/schema/` | Schema-driven create/update form metadata. |
| `GET` | `/api/v1/admin/tables/{table}/` | Paginated global list. Query: `page`, `page_size`, `search`, `date_from`, `date_to`. |
| `POST` | `/api/v1/admin/tables/{table}/` | Create a mutable table record. |
| `GET` | `/api/v1/admin/records/{table}/{id}/` | Detail plus related file references. |
| `PATCH` | `/api/v1/admin/records/{table}/{id}/` | Partial update for mutable tables. Writes audit action `update`. |
| `DELETE` | `/api/v1/admin/records/{table}/{id}/` | Soft delete through admin audit tombstone. Does not physically delete the DB row. |

## Monitoring and Logs

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/api/v1/admin/overview/` | KPIs, table counts, operational alerts. |
| `GET` | `/api/v1/admin/activity/` | Recent activity derived from table timestamps. |
| `GET` | `/api/v1/admin/request-logs/` | Structured request metadata for `/api/v1/*`. Query: `method`, `status_class`, `status_code`, `path`, `search`, date bounds. |
| `GET` | `/api/v1/admin/audit-logs/` | Admin mutation audit trail. Query: `action`, `table`, `record_id`, `actor_email`, `search`, date bounds. |
| `GET` | `/api/v1/admin/logs/` | Raw allow-listed streams. Query: `stream=runtime|api-errors`, `lines <= 500`. |

## Storage

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/api/v1/admin/storage/objects/` | List configured bucket objects. Query: `prefix`, `orphan`, pagination. |
| `GET` | `/api/v1/admin/files/presign/` | Generate short-lived preview/download URL. Query: `bucket`, `object_key`, `mode=preview|download`. |
| `POST` | `/api/v1/admin/files/upload/` | Multipart upload for `care_logs`, `expenses`, `documents`. |