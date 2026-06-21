# CareBridge Full Stack Implementation And Gap Report

> Review date: 2026-06-21
> Scope: `backend/` Django backend, `CareBridge/` SwiftUI iOS frontend, Docker-facing backend configuration, and source-delivery development documents.
> Note: this file keeps the original filename so existing links continue to work, but the report now covers both backend and frontend.
> Update 2026-06-21: the three P0 issues (chat WebSocket auth/membership, AI prompt de-identification, SOS backend wiring with 119 removed) have been implemented and covered by tests; see the Cross-Stack Gaps table for per-item status.

## Validation Performed

| Area | Check | Result |
|---|---|---|
| Backend | Parsed 238 backend Python files with AST, excluding local virtualenvs. | Passed. |
| Backend | `python manage.py check` through `backend\.venv\Scripts\python.exe`. | Passed. |
| Backend | `python manage.py test --verbosity 1` from `backend/`. | Passed, 185 tests (180 baseline + 5 added for the P0 fixes). |
| Backend | `python manage.py makemigrations --check --dry-run`. | Passed, no model changes detected. |
| Backend | `python manage.py migrate --check` against local SQLite. | Failed because local `backend/db.sqlite3` has unapplied migrations; this is local DB state, not missing migration files. |
| Backend | `docker compose config` from `backend/docker`. | Parsed successfully. It warns that the Compose `version` field is obsolete. Do not paste this output publicly because it expands `.env` secrets. |
| Frontend | Static review of 42 Swift source/test files under `CareBridge/`, `CareBridgeTests/`, and `CareBridgeUITests/`. | Completed. |
| Frontend | Reviewed app entry, API client, endpoint catalog, real/mock data services, HealthKit sync, WebSocket clients, upload/privacy services, and major SwiftUI feature views. | Completed. |
| Frontend | Xcode build and Swift/iOS test execution. | Not run in this Windows workspace; requires macOS/Xcode. |

One backend test warning appeared when a health WebSocket broadcast could not connect to `redis:6379`; the exception is caught and all tests passed. Docker should be used when validating Redis/Channels behavior.

## Executive Summary

CareBridge is substantially implemented across backend and iOS frontend for the MAIC competition demo. The backend already covers authentication, family groups, chat, care logs, medication, expenses/documents, HealthKit ingestion, notifications, SOS, admin APIs, and AI assistant workflows. The iOS app has real `APIDataService` integration, SwiftUI screens for most product areas, HealthKit sync, local upload redaction, receipt scanning UI, document preview, chat, AI, and profile flows.

The project is not yet fully production-safe, but the three highest-risk P0 issues have been fixed (2026-06-21): the chat WebSocket consumer now enforces the existing JWT auth middleware + room membership and no longer trusts a client-supplied sender id; AI care-analysis/handover prompts de-identify care-log free text before GPT calls; and the SOS screen now calls the backend SOS endpoint (notifying family in-app) instead of dialing 119 with hardcoded member names. The remaining notable cross-stack risks are: iOS date decoding is incompatible with typical Django fractional-second timestamps, APNs registration can silently fail before login, and authorization is coarse in several backend workflows.

For source-code submission, the codebase is coherent enough to explain, but the report below should be treated as the implementation truth: several visible frontend flows are still demo-like or partially wired even when the backend service exists.

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

## Implemented Frontend Capabilities

### App Foundation

- `CareBridge/App/CareBridgeApp.swift` boots the app with real `APIDataService`, user/profile stores, feature stores, locale store, and HealthKit sync manager.
- `CareBridge/Services/AppConfig.swift` centralizes REST and WebSocket base URLs for simulator, device LAN, and Cloudflare Tunnel modes.
- `CareBridge/Services/APIEndpoint.swift` centralizes backend route paths.
- `CareBridge/Services/APIClient.swift` supports response-envelope decoding, bearer token injection, token refresh retry, multipart upload, and text/event-stream consumption.
- `CareBridge/Services/DataService.swift` defines the app-wide backend contract; `MockDataService.swift` remains available for previews/tests.

### Auth, Profile, And Family

- Login/register/join-family flows are implemented in SwiftUI and call backend auth APIs through `APIDataService+Auth.swift`.
- Access and refresh tokens are stored through `KeychainService`.
- Profile, family invite code display, member list, language selection, notification settings, and health sync ownership controls are present.
- Biometric helper code exists for local token-protected login UX.

### Daily Care And Collaboration

- Home dashboard integrates care logs, todos, calendar, medications, notifications, and health summary data.
- Care log, todo/calendar, board purchase/request, leave, medication, notification, and chat screens exist and use the real data service.
- Chat has REST loading plus a WebSocket client for live messages.
- Translation fields are modeled in several frontend models, and the UI has localized formatting helpers.

### AI, SOS, And Emergency UI

- AI assistant and first-aid screens call the backend AI APIs, including SSE streaming paths in `APIDataService+AI.swift`.
- SOS service method exists in `APIDataService+SOS.swift` for `POST /sos/trigger/`.
- The SOS screen includes CoreLocation handling and calls the backend SOS endpoint; family members are notified in-app (no 119 dialing).

### HealthKit And Health UI

- `HealthKitSyncManager` implements HealthKit authorization, observer/anchored query syncing, sync cursors, and upload of heart rate, blood oxygen, step count, and active energy samples.
- `HealthLiveSocket` listens to backend health live updates.
- Health monitor UI shows heart rate, blood oxygen, blood pressure, blood sugar, weight, charts, alerts, and threshold settings.

### Expense, Receipt, Document, And Privacy

- Spending UI supports camera/photo receipt capture, local Vision OCR parsing, confirmation, quarantine upload, and expense creation.
- `PrivacyRedactionService` strips image metadata and applies Vision-based face/text PII masking for images before upload.
- Document upload, status display, processed URL preview, and QuickLook preview are implemented.
- Local PDF bytes are not redacted on-device; backend DLP/safe preview flow is responsible for server-side privacy.

### Frontend Tests

- Swift test files cover API client behavior, AI data service paths, app config URL selection, health data models, document model behavior, threshold settings, user/todo models, and selected localized formatters.
- These tests were inspected statically only; they were not executed in this Windows environment.

## Cross-Stack Gaps And Risks

| Priority | Gap | Evidence | Recommended fix |
|---|---|---|---|
| P0 ✅ Resolved (2026-06-21) | Chat WebSocket now enforces JWT auth + room membership and ignores any client-supplied sender id. | `apps/chat/consumers.py` `connect()` closes anonymous (4401) and non-member (4403) connections via a `ChatMember` check, mirroring `HealthConsumer`; `receive()` derives the sender from `scope['user'].id` only and the `sender_id` fallback was removed. Regression tests: `apps/chat/tests.py::ChatConsumerAuthTests` (no-token reject, non-member reject, member connect + sender-from-token). | Done. |
| P0 ✅ Resolved (2026-06-21) | AI care-analysis and handover prompts de-identify care-log free text before GPT calls. | `apps/ai_assistant/views.py` routes care-log `content` (and handover `recorder__name`) through `_safe_json`/`_safe_text` (reused from `apps/ai_assistant/domain_queries.py`, backed by `core.deidentification.prepare_text_for_gpt`); raw vitals are kept only for server-side numeric metric extraction. Regression tests: `AIPromptDeidentificationTests`. | Done. |
| P0 ✅ Resolved (2026-06-21) | SOS triggers the backend and notifies family in-app; 119 dialing removed. | `CareBridge/Views/SOS/SOSView.swift` now calls `service.triggerSOS(location:)` (returns the notified-member count) and shows the real count; `tel://119` and the hardcoded member list were removed. `triggerSOS` returns `Int` across `DataService`/`APIDataService+SOS`/`MockDataService`. Backend `POST /sos/trigger/` already creates per-member `Notification` rows (in-app delivery via the notification center; APNs stays a no-op until configured, per the V2 plan). | Done. |
| P1 | iOS date decoding is incompatible with Django fractional-second ISO timestamps. | `APIClient.makeDecoder`, `ChatWebSocket`, `HealthLiveSocket`, and AI stream decoder use `.iso8601`; several models hard-decode `Date`. | Add one shared ISO8601 decoder that accepts fractional seconds and offsets, then add tests for timestamps such as `2026-06-08T18:57:09.161369+08:00`. |
| P1 | APNs device-token registration can silently fail. | `CareBridgeApp.didRegisterForRemoteNotificationsWithDeviceToken` calls `try? await APIDataService().registerPushToken(token)` before guaranteed login; no retry after login was found. | Store token, retry after successful login/profile load, surface failure in logs, and verify APNs entitlement/config. |
| P1 | Receipt OCR is frontend-local only; backend OCR extraction is not implemented. | Spending UI uses Vision OCR and then creates an expense; backend expense creation schedules redaction, not OCR parsing. | Decide whether local OCR is enough for competition. If backend OCR is claimed, add a backend OCR/LLM parsing task after de-identification. |
| P1 | Medication reminder task exists but is not scheduled. | Backend task exists, but Celery beat only schedules cleanup tasks. | Add a beat schedule and verify `celery-beat` and `celery-worker` in Docker. |
| P1 | Chat unread/read receipt behavior is placeholder. | Backend serializers return unread count as `0`; frontend displays unread badges from that field. | Add per-member last-read/read-state tracking and update frontend read APIs. |
| P1 | First-aid RAG does not use real pgvector search. | Embedding data is stored in text and searched in memory/keyword fallback. | Add a pgvector field/migration and database-side vector search when privacy/security blockers are fixed. |
| P1 | Authorization is too coarse in several backend workflows. | `IsFamilyAdmin` exists but is not broadly applied; todo assignee validation can accept a user outside the family. | Apply family admin/primary caregiver checks and validate all foreign-key ownership inputs. |
| P2 | Forgot-password flow is UI-only and backend routing is incomplete. | `ForgotPasswordView` only sets `isSent = true`; backend reset serializers exist but no routed flow is exposed. | Implement token generation, email delivery or demo-safe reset code, endpoint routing, and frontend API call. |
| P2 | Frontend logout does not call backend logout or clear all session state. | `ProfileView` sets `isLoggedIn = false` only. | Call `service.logout()`, clear Keychain tokens, disable HealthKit sync, and reset stores. |
| P2 | JWT logout blacklisting may not be active. | Backend logout catches blacklist absence; `token_blacklist` app is not installed. | Add SimpleJWT blacklist app and migrations, or explicitly document stateless logout. |
| P2 | WebSocket JWT is passed in the query string. | Chat and health sockets append `?token=`. | Backend must sanitize logs. Prefer a subprotocol/header-compatible auth path if supported by the client/server stack. |
| P2 | Several frontend service filters are accepted but ignored. | `fetchExpenses(month:)`, `fetchSpendingSummary(month:)`, `fetchCalendarEvents(month:)`, and health `elderId` methods do not send query parameters. | Add query support or remove misleading parameters until backend filtering is used. |
| P2 | Health UI has duplicate HealthKit paths and partial backend integration. | `HealthMonitorView` has its own `HealthKitManager` while `HealthKitSyncManager` also uploads HealthKit data; day/week/month range selector is visual only. | Consolidate HealthKit reads through one manager and back chart/range UI with backend historical queries. |
| P2 | Health threshold UI shows BP/sugar controls but saves only heart rate and blood oxygen. | `HealthThresholdSettingsView.saveThresholds()` sends only `heartRateHigh`, `heartRateLow`, and `bloodOxygenLow`. | Either hide BP/sugar threshold controls or add backend fields and alert rules. |
| P2 | Document redaction does not output redacted PDFs. | Backend document task creates safe text preview; binary PDF redaction is not supported. | Decide whether safe preview is enough for the demo, or add redacted PDF generation. |
| P2 | Some notification types are modeled but not triggered. | Trigger coverage exists for health/chat/leave/SOS and unscheduled medication reminders; other types remain unused. | Add triggers for todo assignment, event reminders, expense scanned, board status, and medication confirmed. |
| P2 | Frontend family invite code display is inconsistent. | Profile top section uses `familyInviteCode`, but `FamilyMembersView` displays `userStore.currentUser?.family?.id` prefix as an invite code. | Use the real invite code field everywhere. |
| P2 | Public API target is hard-coded in source. | `AppConfig.mode` is committed as `.publicTunnel`; LAN IP is hard-coded for `.device`. | Move target selection to build configuration, `.xcconfig`, or launch arguments for team/demo builds. |
| P2 | iOS background modes need validation. | `Info.plist` has `fetch` and `processing`; no `BGTaskSchedulerPermittedIdentifiers` was found. `aps-environment` was not found in source entitlements. | Verify signing capabilities in Xcode. Remove unused background mode or add BG task identifiers; confirm push entitlement. |
| P2 | UI localization is incomplete. | Many screens contain hard-coded Traditional Chinese strings; `SupportedLanguage.uiLocale(for:)` maps unsupported UI languages to English. | Decide required competition languages and complete `Localizable.xcstrings` plus frontend string extraction. |
| P2 | Docker Compose file uses obsolete `version`. | `docker compose config` reports the warning. | Remove top-level `version` when touching Docker config next. |

## Frontend Detailed Notes

### Real Implementation Present

The frontend is not only a mock shell. Most major screens use the real `DataService` abstraction and `APIDataService` implementations. The service layer covers auth, family, chat, care logs, medication, expenses, documents, health, AI, notifications, SOS, calendar, todo, leave, and board flows. HealthKit sync and local image privacy redaction are meaningful implemented features.

### Demo Or Partial Implementation Still Visible

- Forgot password shows success without a network call.
- Home weekly steps falls back to sample values on backend/network failure; the DTO itself matches the backend `[Int]` contract, so this is a fallback-UX choice rather than a contract bug.
- Receipt OCR is a client-side helper, not the backend OCR pipeline described in product goals.
- Health charts and range selector are more visual than data-driven; backend historical/range data is not fully used.
- Some settings screens show options that are not persisted or not backed by backend fields.

### Contract Fragility

The biggest frontend contract issue is timestamp decoding. Django/DRF commonly returns fractional seconds and timezone offsets. Swift `.iso8601` decoding often rejects these formats unless the formatter is configured with fractional seconds. Several models either fail hard or silently replace failed dates with `Date()`, which can make lists and alerts appear current when they are not.

A secondary contract issue is parameter drift: several frontend method signatures suggest filtering (for example `month:` and `elderId:`) but send no matching query parameters. Note that weekly steps was previously flagged as a DTO mismatch; on review the backend `weekly-steps` endpoint returns a 7-element `[Int]` array (`apps/health/views.py`) that matches the iOS `fetchWeeklySteps(elderId:) -> [Int]` contract, so that item has been removed.

### Privacy Status

The privacy architecture is directionally correct: frontend strips image metadata and tries local face/text masking, backend stores quarantine keys, DLP redacts asynchronously, and processed presigned URLs are exposed after processing. AI report prompts now de-identify care-log free text before GPT calls (via `core.deidentification`). Remaining gaps are explicit: backend receipt OCR should only parse de-identified content if implemented, and PDFs currently have safe text preview rather than redacted binary output.

## Recommended Fix Order

Completed 2026-06-21: (a) chat WebSocket JWT auth + room membership enforcement and removal of the `sender_id` fallback, (b) AI report prompt de-identification before GPT calls, (c) SOS frontend wired to `POST /sos/trigger/` with 119 dialing removed (family notified in-app).

Remaining, in order:

1. Replace all Swift date decoding paths with one fractional-second-compatible decoder and add regression tests.
2. Fix APNs registration retry after login and verify push/background entitlements in Xcode.
3. Schedule medication reminders in Celery beat and verify worker/beat parity in Docker.
4. Tighten backend family/admin authorization and todo assignee validation.
5. Decide whether backend receipt OCR and redacted PDF output are required for the competition demo.
6. Clean up frontend demo-only settings: forgot password, logout/session clearing, health thresholds, family invite code, and ignored filters.
7. Move `AppConfig` target selection out of source edits before multi-device/team testing.
8. Convert first-aid embeddings to pgvector after the security/privacy fixes.

## Documentation Cleanup Result

The formal docs are consolidated under `Doc/`:

- `Doc/PRD.md`
- `Doc/Architecture_Plan.md`
- `Doc/API_Documentation.md`
- `Doc/Backend_Implementation_Gap_Report.md`

Old root-level task lists, frontend handoff notes, Gemma migration drafts, and stale diagram Markdown were removed or merged into the curated documents above. The current report should be treated as the latest full-stack implementation/gap status.
