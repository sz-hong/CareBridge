# CareBridge Admin Dashboard Integration Guide

This guide explains how the personal website admin dashboard should call the CareBridge staff-only backend API.

## Base URLs

Production API base:

```text
https://api.carebridge-lab.com/api/v1
```

Admin API base:

```text
https://api.carebridge-lab.com/api/v1/admin
```

Local Django development base:

```text
http://127.0.0.1:8000/api/v1
```

Allowed browser origins:

| Environment | Origin |
|---|---|
| Production dashboard | `https://shao-zhen.com` |
| Vite preview | `http://127.0.0.1:4173` |
| Astro dev | `http://localhost:4321` |

The API uses bearer tokens. Do not send cookies or browser credentials.

```ts
fetch(url, {
  headers: { Authorization: `Bearer ${accessToken}` },
  credentials: "omit",
});
```

## Authentication Flow

1. Sign in through the existing API login endpoint.
2. Store the returned `access` token in the dashboard session state.
3. Send `Authorization: Bearer <access_token>` to every admin request.
4. Refresh or re-login when the backend returns `401`.

Login request:

```http
POST https://api.carebridge-lab.com/api/v1/auth/login/
Content-Type: application/json
```

```json
{
  "email": "staff@example.com",
  "password": "your-password"
}
```

The login user must be active staff. Admin API authorization requires:

- `is_authenticated = true`
- `is_active = true`
- `is_staff = true`

Expected auth failures:

| HTTP | Meaning | Frontend behavior |
|---:|---|---|
| `401` | Missing, expired, or invalid JWT | Clear session and show login. |
| `403` | User is authenticated but not staff | Show access denied. |

## Fetch Helper

Use one small client wrapper so every admin screen handles envelopes and auth consistently.

```ts
const API_BASE = "https://api.carebridge-lab.com/api/v1";

type ApiEnvelope<T> =
  | { success: true; data: T; meta?: unknown }
  | { success: false; error: { code: string; message: string } };

export async function adminGet<T>(
  path: string,
  accessToken: string,
  params?: Record<string, string | number | boolean | undefined>,
): Promise<T> {
  const url = new URL(`${API_BASE}/admin/${path.replace(/^\/+/, "")}`);

  Object.entries(params ?? {}).forEach(([key, value]) => {
    if (value !== undefined) url.searchParams.set(key, String(value));
  });

  const response = await fetch(url, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    credentials: "omit",
  });

  const body = (await response.json()) as ApiEnvelope<T>;

  if (!response.ok || !body.success) {
    const message =
      body.success === false ? body.error.message : `HTTP ${response.status}`;
    throw new Error(message);
  }

  return body.data;
}
```

## Endpoint Summary

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/admin/overview/` | Global KPIs, table counts, and operational alerts. |
| `GET` | `/admin/activity/` | Recent activity inferred from model timestamps. |
| `GET` | `/admin/tables/{table}/` | Paginated read-only table viewer. |
| `GET` | `/admin/records/{table}/{id}/` | Single record detail plus related storage files. |
| `GET` | `/admin/storage/objects/` | Configured bucket object inventory and orphan status. |
| `GET` | `/admin/logs/` | Tail allow-listed backend log streams. |

Admin endpoints accept `GET` and CORS `OPTIONS` only.

## Allow-Listed Tables

Use only these table names in route params:

```ts
export const ADMIN_TABLES = [
  "users",
  "families",
  "care_logs",
  "board_requests",
  "todos",
  "events",
  "health_data",
  "health_alerts",
  "health_thresholds",
  "expenses",
  "documents",
] as const;
```

Unknown table names return `404`.

## Overview

```ts
type AdminOverview = {
  kpis: Array<{ label: string; value: number; delta_24h: number }>;
  tables: Array<{
    table: string;
    count: number;
    created_24h: number;
    updated_24h: number;
  }>;
  alerts: Array<{ severity: string; title: string; count: number }>;
};

const overview = await adminGet<AdminOverview>("overview/", accessToken);
```

Use this endpoint for the dashboard landing screen: KPI tiles, table summary, and alert badges.

## Activity

Query params:

| Param | Default | Max | Notes |
|---|---:|---:|---|
| `limit` | `12` | `100` | Number of items. |
| `since` | none | n/a | ISO datetime lower bound. |
| `cursor` | none | n/a | ISO datetime cursor for older items. |

```ts
type AdminActivity = {
  results: Array<{
    id: string;
    table: string;
    record_id: string;
    action: "created" | "updated";
    actor: string | null;
    created_at: string | null;
  }>;
  next_cursor: string | null;
};

const activity = await adminGet<AdminActivity>("activity/", accessToken, {
  limit: 20,
});
```

Activity is inferred from `created_at` and `updated_at`. It is not a full audit trail.

## Table Viewer

Query params:

| Param | Default | Max | Notes |
|---|---:|---:|---|
| `page` | `1` | n/a | Page number. |
| `page_size` | `20` | `100` | Values above `100` are capped. |
| `search` | none | n/a | Searches table-specific safe fields only. |
| `date_from` | none | n/a | ISO date or datetime lower bound. |
| `date_to` | none | n/a | ISO date or datetime upper bound. |

```ts
type AdminTablePage<TRecord = Record<string, unknown>> = {
  results: TRecord[];
  count: number;
  next: number | null;
  previous: number | null;
  page: number;
  page_size: number;
};

const users = await adminGet<AdminTablePage>("tables/users/", accessToken, {
  page: 1,
  page_size: 50,
  search: "staff@example.com",
});
```

List responses exclude sensitive fields such as passwords, tokens, secrets, credentials, and APNs-related fields.

## Record Detail

```ts
type RelatedFile = {
  bucket: string | null;
  object_key: string;
  size: number | null;
  last_modified: string | null;
  content_type: string | null;
  linked_table: string;
  linked_record_id: string;
  orphan: false;
};

type AdminRecordDetail<TRecord = Record<string, unknown>> = {
  record: TRecord;
  related_files: RelatedFile[];
  raw: TRecord;
};

const expense = await adminGet<AdminRecordDetail>(
  `records/expenses/${expenseId}/`,
  accessToken,
);
```

`related_files` is parsed from safe URL fields such as `file_url`, `image_url`, `photo_url`, and `avatar_url`.

The first version does not return signed preview or download URLs.

## Storage Objects

Query params:

| Param | Default | Max | Notes |
|---|---:|---:|---|
| `bucket` | configured bucket | n/a | Omit it unless you need to display the configured bucket name. |
| `prefix` | empty | n/a | Rejects path traversal. |
| `page` | `1` | n/a | Page number. |
| `page_size` | `20` | `100` | Values above `100` are capped. |
| `orphan` | none | n/a | Use `true` or `false` to filter. |

```ts
type StorageObjectPage = {
  results: Array<{
    bucket: string;
    object_key: string;
    size: number | null;
    last_modified: string | null;
    content_type: string | null;
    linked_table: string | null;
    linked_record_id: string | null;
    orphan: boolean;
  }>;
  count: number;
  page: number;
  page_size: number;
};

const storage = await adminGet<StorageObjectPage>(
  "storage/objects/",
  accessToken,
  { prefix: "receipts/", orphan: true },
);
```

The frontend never sends MinIO or S3 secrets. The backend uses its configured credentials.

## Logs

Allowed streams:

| Stream | Purpose |
|---|---|
| `runtime` | General runtime log. |
| `api-errors` | API error log. |

Query params:

| Param | Default | Max | Notes |
|---|---:|---:|---|
| `stream` | `runtime` | n/a | Must be `runtime` or `api-errors`. |
| `lines` | `100` | `500` | Values above `500` are capped. |

```ts
type LogTail = {
  stream: "runtime" | "api-errors";
  lines: Array<{
    timestamp: string | null;
    level: "DEBUG" | "INFO" | "WARNING" | "ERROR" | "CRITICAL";
    message: string;
    request_id: string | null;
  }>;
  next_cursor: string | null;
};

const logs = await adminGet<LogTail>("logs/", accessToken, {
  stream: "api-errors",
  lines: 200,
});
```

Do not expose a free-form file path input in the UI. The backend rejects unknown streams and path traversal.

## Recommended Screens

Start with these dashboard screens:

| Screen | Endpoint |
|---|---|
| Overview | `/admin/overview/` and `/admin/activity/` |
| Database Explorer | `/admin/tables/{table}/` |
| Record Drawer | `/admin/records/{table}/{id}/` |
| Storage Inventory | `/admin/storage/objects/` |
| Logs | `/admin/logs/` |

## Error Handling Checklist

- On `401`, clear the stored access token and redirect to login.
- On `403`, show an access denied state.
- On `404`, show a not found state for unknown tables or records.
- On `400`, show the backend validation message.
- On `502` from storage, show that storage inventory is temporarily unavailable.
- Keep `credentials: "omit"` because the backend CORS configuration is bearer-token based.
