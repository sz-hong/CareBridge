# CareBridge PRD

> Last updated: 2026-06-21
> Scope: MAIC competition source submission
> Implementation status notes focus on the Django backend. iOS runtime behavior should be verified separately on macOS/Xcode.

## Product Summary

CareBridge is a care-coordination system for elders, caregivers, and family members. It centralizes daily care tasks, cross-language communication, HealthKit / Apple Watch data, emergency workflows, receipts, documents, and AI-assisted summaries into one shared care workspace.

## Users

| User | Primary needs |
|---|---|
| Elder | Passive health monitoring, SOS support, low-friction safety workflow. |
| Caregiver | Record daily care, confirm medication, request purchases or leave, communicate across languages. |
| Family member | Manage the family workspace, review health/care status, approve requests, receive alerts, inspect expenses and documents. |
| Staff admin | Inspect system data, storage, request logs, and runtime logs for support/demo operations. |

## Product Goals

1. Make daily elder-care coordination visible to the whole family.
2. Reduce language friction between foreign caregivers and Taiwanese families.
3. Turn HealthKit / Apple Watch data into actionable alerts and summaries.
4. Keep sensitive receipts, documents, and AI inputs behind a de-identification workflow.
5. Provide emergency and first-aid guidance while clearly avoiding replacement of professional medical advice.

## Non-Goals For Current Submission

- Full medical diagnosis or autonomous clinical decision-making.
- A cloud VM production deployment; the current backend is local Docker plus Cloudflare Tunnel.
- Full offline-first sync for all iOS modules.
- Complete OCR automation for receipts.
- Complete document redaction for original PDF binary output.

## Feature Scope

| Area | Requirement | Current backend status |
|---|---|---|
| Authentication | Register, login, refresh token, profile, logout, delete account, join family. | Mostly implemented. Password reset serializers exist but no routed reset flow is exposed. |
| Family workspace | Create/list/update/delete family, invite code, member list, member removal, health sync binding. | Implemented. Admin/primary-member enforcement needs tightening. |
| Chat and translation | Family/private rooms, REST messages, WebSocket delivery, translated fields. | Implemented with a security gap in WebSocket authentication/membership checks. |
| Board requests | Purchase/household requests, status workflow, reply, translated item names/notes. | Implemented. Role-specific approval rules need tightening. |
| Leave requests | Request, approve/reject, vote, auto-resolve, calendar event creation. | Implemented. Role-specific approval rules need tightening. |
| Calendar | Event CRUD, batch/date/type filters, translated title/note. | Implemented. |
| Todos | Todo CRUD, status filters, completion creates activity care log. | Implemented. Assignee family validation is incomplete. |
| Care logs | Timeline records, JSON content, date/type filters, summaries, selected field translation. | Implemented. Raw care-log text is still used by some AI report prompts. |
| Medication | Medication CRUD, active filtering, confirmation, today confirmations, care-log creation. | Implemented. Reminder task exists but is not scheduled in Celery Beat. |
| Expenses | Manual expense records, upload URL, quarantine key validation, de-identification task, monthly summary. | Partially implemented. Receipt OCR parsing is not implemented. |
| Documents | Upload URL, quarantine key validation, DLP de-identification, safe text preview, processed URL exposure. | Partially implemented. Redacted PDF binary output is not supported. |
| Health | Health data sync, threshold checks, alerts, acknowledge, dashboard, weekly steps, WebSocket broadcast. | Implemented for core metrics. Coverage is limited to current model types and threshold logic. |
| Notifications | Notification list/read/read-all, device token registration, APNs helper, Celery tasks. | Partially implemented. Several notification types are modeled but not triggered. |
| SOS | Trigger/history/resolve, family notifications, APNs task. | Implemented. |
| AI assistant | Chat, SSE streaming, function tools, care analysis, handover report, subsidy form, first-aid RAG. | Partially implemented. Some AI paths need stronger de-identification; pgvector integration is incomplete. |
| Admin API | Staff-only overview, table CRUD for allow-listed tables, storage helpers, request logs, runtime logs. | Implemented. |

## Privacy Requirements

Sensitive upload and AI flows must follow this policy:

1. Client strips metadata and performs local redaction where possible.
2. Raw uploads go to `quarantine/{family_id}/...`.
3. Backend stores object keys, not public raw URLs.
4. Celery runs de-identification and writes processed output to `processed/{family_id}/...`.
5. APIs expose processed presigned URLs only after processing.
6. GPT prompts should receive de-identified text or aggregate data, not raw OCR/document/care-note content.

## Acceptance Priorities

| Priority | Requirement |
|---|---|
| P0 | Authenticated users cannot read/write another family's data through REST, WebSocket, or AI tools. |
| P0 | Raw uploaded files and raw PII findings are not exposed through public API responses. |
| P0 | Docker Compose can start `web`, `db`, `redis`, `minio`, `celery-worker`, and `celery-beat`. |
| P1 | Core workflows work end to end: family, chat, care log, medication confirmation, health sync, SOS, document/receipt upload. |
| P1 | AI reports use de-identified or aggregate records where feasible. |
| P2 | Receipt OCR, richer health metrics, read receipts, and broader notification triggers are completed after the competition submission. |
