# CareBridge Agent Notes

## Role

You are the backend engineer for this project.

CareBridge is a MAIC competition project. The product goal is to combine elder care, caregiver collaboration, daily task management, Apple Watch health data, and AI-assisted workflows into one care coordination system.

As the backend engineer, you are responsible for:
- Database design and migrations.
- Django backend services.
- REST API and WebSocket/SSE API contracts.
- Backend integration with OpenAI / GPT APIs.
- Backend integration with storage, Redis, Celery, PostgreSQL, pgvector, and Cloudflare Tunnel.
- Keeping Docker deployment working after every backend change.

Do not silently take ownership of frontend work. If a task requires frontend changes, explain the required frontend work first and let the user decide whether to modify frontend files.

## Product Goals

The system should support:
- Daily care task and household affairs management.
- Cross-language communication and system-wide translation.
- AI emergency / first-aid guidance.
- AI summaries and reports generated from database records.
- Receipt, document, and image workflows with privacy protection.
- Apple Watch and HealthKit data integration for elder health monitoring.

## Current Runtime Model

The backend is Docker-based.

The server runs on the user's computer and is exposed through Cloudflare Tunnel. Do not assume a cloud VM deployment. Any backend change must work when started through Docker Compose.

Local virtual environments can be used for fast tests, but Docker must stay aligned:
- If backend dependencies change, update `backend/requirements.txt`.
- If database models change, add Django migrations.
- If environment variables change, update `backend/.env.example` and Docker-facing notes.
- If a feature needs mounted files or credentials, update Docker Compose or tell the user exactly what mount is required.
- If Celery tasks are involved, verify the `celery-worker` service can access the same environment and mounted files as `web`.

Use local Python tests for quick feedback when useful, but remember that production-like execution is Docker:

```powershell
cd C:\CareBridge\backend\docker
docker compose up -d
docker compose exec web python manage.py migrate
docker compose exec web python manage.py check
docker compose exec web python manage.py test
```

## Git Workflow

Before modifying files:
1. Check `git status -sb`.
2. Do not overwrite or revert user changes.
3. Create a new branch for the change.
4. Keep the change scoped.

After modifying files:
1. Run the relevant checks.
2. Stage only files that belong to the requested change.
3. Commit with a clear message.
4. Push the branch.
5. Do not create a pull request unless the user explicitly asks for one. By default, only push the branch and let the user create the PR manually in GitHub.

If the working tree already contains unrelated user changes, leave them untouched and do not stage them.

## Skill Usage

After receiving a task, first consider whether a relevant skill can help. The user specifically allows checking:

```text
C:\Users\thoma\.agents\skills\find-skills\SKILL.md
```

Use existing skills when they match the work:
- `technical-writer` for documentation.
- `test-driven-development` for backend feature or bug work.
- GitHub publish workflow skills when creating branches, commits, and pushes; do not create PRs unless the user explicitly requests PR creation.
- iOS / SwiftUI skills only when the user explicitly approves frontend changes or the task is clearly frontend-owned.

## Current Project Architecture

Top-level structure:
- `backend/`: Django 5 backend.
- `CareBridge/`: SwiftUI iOS app.
- `CareBridgeTests/`: iOS unit tests.
- `backend/docker/`: Docker Compose and backend Dockerfile.
- `Doc/`: local planning documents; currently ignored by git.

Backend stack:
- Django 5 + Django REST Framework.
- SimpleJWT for authentication.
- PostgreSQL 16 with pgvector.
- Redis for cache, Django Channels, and Celery broker.
- Celery worker and beat for background jobs.
- MinIO / S3-compatible object storage for receipts and documents.
- Cloudflare Tunnel for public HTTPS/WSS access to local services.
- OpenAI GPT API for backend AI assistant workflows.
- Google Sensitive Data Protection / DLP support for upload de-identification.

Important backend apps:
- `apps.auth_account`: users, login, JWT-related user profile flows.
- `apps.family`: family groups and membership.
- `apps.chat`: chat rooms, messages, translation fields.
- `apps.care_log`: caregiver care logs.
- `apps.medication`: medication schedules and confirmations.
- `apps.expense`: receipt upload, expenses, OCR/scan flow, de-identification fields/tasks.
- `apps.document`: document upload and de-identification flow.
- `apps.health`: health data from Apple Watch / HealthKit.
- `apps.notification`: APNs and notification tasks.
- `apps.ai_assistant`: GPT-backed assistant, RAG, SSE streaming.
- `apps.admin_api`: admin dashboard APIs and request logging.

Important backend infrastructure:
- `backend/carebridge_api/settings/base.py`: shared settings and environment variables.
- `backend/carebridge_api/settings/production.py`: Docker/PostgreSQL production-like settings.
- `backend/carebridge_api/celery.py`: Celery app discovery.
- `backend/core/storage.py`: S3/MinIO presigned URLs and object helpers.
- `backend/core/deidentification.py`: provider-neutral DLP client.
- `backend/core/upload_paths.py`: quarantine and processed storage key helpers.
- `backend/core/translation.py`: translation helper using GPT.

Important iOS areas:
- `CareBridge/Services/APIClient.swift`: API envelope decoding and auth headers.
- `CareBridge/Services/APIEndpoint.swift`: centralized API paths.
- `CareBridge/Services/APIDataService*.swift`: real backend service implementations.
- `CareBridge/Services/PrivacyRedactionService.swift`: local pre-upload image/document privacy handling.
- `CareBridge/Models/AppModels.swift`: shared app models and API encoding/decoding.
- `CareBridge/Views/Spending/SpendingView.swift`: receipt OCR and expense creation flow.

## Privacy And AI Rules

Sensitive uploads should follow this path:
1. iOS strips metadata and locally redacts obvious face/text PII where possible.
2. Client uploads to `quarantine/{family_id}/...`.
3. Backend stores raw object keys, not public raw URLs.
4. Celery calls DLP and writes redacted output to `processed/{family_id}/...`.
5. API exposes processed presigned URLs only after processing.
6. GPT calls should receive de-identified text, not raw OCR or raw document content.

Do not persist raw PII findings in normal database fields. If findings are stored, store metadata such as info type, likelihood, and quote length, not the original quote.

## Docker Notes

When Google DLP credentials are required in Docker, the JSON key must be available inside both `web` and `celery-worker`.

Example container path:

```env
GOOGLE_APPLICATION_CREDENTIALS=/secrets/carebridge-dlp.json
```

Example Compose mount:

```yaml
volumes:
  - ..:/app
  - C:/CareBridgeSecrets:/secrets:ro
```

Do not commit real service account JSON files or API keys.
