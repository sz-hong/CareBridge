# Backend Implementation And Gap Report

> Review date: 2026-06-21
> Scope: `backend/` Django codebase, Docker-facing backend configuration, backend API/runtime documents.

## Validation Performed

| Check | Result |
|---|---|
| Parsed 238 backend Python files with AST, excluding local virtualenvs. | Passed. |
| `python manage.py check` through `backend\.venv\Scripts\python.exe`. | Passed. |
| `python manage.py test --verbosity 1` from `backend/`. | Passed, 180 tests. |
| `python manage.py makemigrations --check --dry-run`. | Passed, no model changes detected. |
| `python manage.py migrate --check` against local SQLite. | Failed because local `backend/db.sqlite3` has unapplied migrations; this is local DB state, not missing migration files. |
| `docker compose config` from `backend/docker`. | Parsed successfully. It warns that the Compose `version` field is obsolete. Do not paste this output publicly because it expands `.env` secrets. |

One local test warning appeared when a health WebSocket broadcast could not connect to `redis:6379`; the exception is caught and all tests passed. Docker should be used when validating Redis/Channels behavior.

## Implemented Backend Capabilities

### Runtime And Infrastructure

- Django 5, Django REST Framework, SimpleJWT, custom response envelope, and custom exception handler.
- Channels/Redis WebSocket infrastructure.
- Celery worker and beat services.
- PostgreSQL 16 pgvector Docker image.
- MinIO / S3-compatible storage helpers and presigned URL helpers.
- Cloudflare Tunnel compatible production settings.
- OpenAI, APNs, and Google DLP configuration paths.

### Auth And Family

- Register, login, token refresh, profile, logout, delete account, and join-family flows.
- Family create/list/retrieve/update/delete, member list/removal, and family health sync binding.

### Communication And Translation

- Chat room CRUD, message REST APIs, WebSocket delivery, text/image/request-card messages.
- OpenAI translation helper with protected entity masking.
- Auto-enroll new family members into existing chats.
- Chat notification creation.

### Daily Care Workflows

- Board request CRUD, status updates, replies, and translated item/note/reply fields.
- Leave request CRUD, status flow, voting, auto-resolve, and calendar event creation.
- Calendar event CRUD, batch/date/type filters, and translated title/note fields.
- Todo CRUD, status filters, and automatic activity care-log creation on completion.
- Care log CRUD, date/type filters, summaries, and selected JSON field translation.

### Medication

- Medication CRUD, active/expired filtering, caregiver read/confirm behavior.
- Confirmation flow creates linked care-log entries.
- Today-confirmations endpoint and translation of medication fields.

### Health

- HealthData sync with family binding owner enforcement.
- Deduplication on `(family, type, recorded_at)`.
- Dashboard latest values, health thresholds, alert creation, alert acknowledge, weekly steps, and health WebSocket broadcast.

### Expense And Document Privacy

- Presigned quarantine upload URLs.
- Rejection of direct raw image/file URLs in newer upload flows.
- Family quarantine key validation.
- Celery DLP redaction/de-identification tasks.
- Processed presigned URL exposure only after processing.
- Cleanup tasks for raw quarantine files.
- Monthly expense summaries.
- Document PDF safe text preview path.

### AI Assistant

- AI chat, SSE streaming, and function-calling tools.
- Safer database tool pattern in `apps.ai_assistant.domain_queries`.
- Care analysis, handover report, subsidy form, uploaded template support.
- First-aid RAG with embeddings/keyword fallback.

### SOS, Notifications, And Admin

- Notification model, list/read/read-all, APNs device registration, APNs helper, and Celery tasks.
- SOS trigger, history, resolve, and notification integration.
- Staff-only admin overview, activity, table schema/list/create/soft-delete, lookup, S3 object, presign/upload, request log, and runtime log APIs.

## Gaps And Risks

| Priority | Gap | Evidence | Recommended fix |
|---|---|---|---|
| P0 | Chat WebSocket accepts connections without authentication or membership validation. | `backend/apps/chat/consumers.py:11` accepts immediately; `backend/apps/chat/consumers.py:27` can fall back to payload `sender_id`. | Require authenticated scope user, validate chat membership before `accept`, and reject client-supplied sender identity. |
| P0 | AI care-analysis and handover report prompts can include raw care-log free text. | `backend/apps/ai_assistant/views.py:369`, `:401`, `:476`, `:531` build prompts from `CareLog.content`. | De-identify/suppress free-text fields before prompt construction, matching the safer `domain_queries` approach. |
| P1 | Receipt OCR is not implemented. | `backend/apps/expense/views.py:139` creates a processing expense and schedules redaction only. | Add OCR/LLM parsing task that extracts store/date/items/total/category after de-identification. |
| P1 | Medication reminder task is not scheduled. | `apps.notification.tasks.send_medication_reminders` exists, but `CELERY_BEAT_SCHEDULE` only includes cleanup tasks. | Add a beat schedule, for example every 5-15 minutes, and verify in `celery-beat`. |
| P1 | Chat unread/read receipts are placeholder behavior. | `backend/apps/chat/serializers.py` returns unread count as `0`. | Add read state model or per-user last-read timestamp. |
| P1 | First-aid RAG does not use a real pgvector column. | `backend/apps/ai_assistant/models.py:36-38` stores embedding in `TextField`; search is in-memory/keyword fallback. | Add pgvector field/migration and database-side vector search. |
| P1 | Role/admin authorization is coarse in several workflows. | `core.permissions.IsFamilyAdmin` exists but is not broadly used. | Apply primary/admin checks to family deletion/member removal and approval/status transitions. |
| P1 | Todo assignee can be outside the user's family. | `backend/apps/todo/views.py` saves `assignee_id` directly. | Validate assignee belongs to `request.user.family`. |
| P2 | Password reset flow is incomplete. | Forgot/reset serializers exist, but no routed view/URL is exposed. | Add token generation, email delivery, reset endpoint, and tests. |
| P2 | JWT logout blacklisting may not be active. | `LogoutView` catches blacklist absence; `token_blacklist` app is not in installed apps. | Add SimpleJWT blacklist app and migrations, or document stateless logout. |
| P2 | Document redaction does not output redacted PDFs. | Document task creates safe text preview; binary PDF redaction is not supported. | Decide whether text preview is enough for competition, or add PDF redaction output. |
| P2 | Some notification types are modeled but not triggered. | Trigger coverage exists for health/chat/leave/SOS and unscheduled medication reminders; other types remain unused. | Add triggers for todo assignment, event reminder, expense scanned, board status, and medication confirmed. |
| P2 | Health scope is limited. | Threshold checks focus on heart rate and blood oxygen; BP is handled as manual care-log data. | Extend health model and alert rules only after iOS HealthKit sync requirements are finalized. |
| P2 | Docker Compose file uses obsolete `version`. | `docker compose config` reports the warning. | Remove top-level `version` when touching Docker config next. |

## Recommended Fix Order

1. Secure Chat WebSocket authentication and membership.
2. De-identify AI report prompts before GPT calls.
3. Schedule medication reminders and verify worker/beat parity in Docker.
4. Add todo assignee family validation and tighten approval/admin permissions.
5. Decide whether receipt OCR and redacted PDF output are required for the competition demo.
6. Convert first-aid embeddings to pgvector after the security/privacy fixes.

## Documentation Cleanup Result

The formal docs are now consolidated under `Doc/`:

- `Doc/PRD.md`
- `Doc/Architecture_Plan.md`
- `Doc/API_Documentation.md`
- `Doc/Backend_Implementation_Gap_Report.md`

Old root-level task lists, frontend handoff notes, Gemma migration drafts, and stale diagram Markdown were removed or merged into the curated documents above.
