# CareBridge

CareBridge is a MAIC competition project for elder-care coordination. The product combines caregiver collaboration, daily task management, Apple Watch / HealthKit health data, privacy-preserving receipt and document workflows, and AI-assisted care summaries.

The repository contains a SwiftUI iOS app and a Docker-based Django backend.

## Project Structure

```text
CareBridge/
├── CareBridge/                 # SwiftUI iOS app
├── CareBridgeTests/            # iOS unit tests
├── CareBridgeUITests/          # iOS UI tests
├── backend/                    # Django 5 backend
│   ├── apps/                   # Backend feature modules
│   ├── carebridge_api/         # Django settings, URLs, ASGI/WSGI, Celery
│   ├── core/                   # Shared backend helpers
│   └── docker/                 # Docker Compose runtime
├── Doc/                        # Source-submission development docs
└── README.md
```

## Backend Runtime

The backend is designed to run locally through Docker Compose and can be exposed through Cloudflare Tunnel for device testing.

```powershell
cd C:\CareBridge\backend\docker
docker compose up -d --build
docker compose exec web python manage.py migrate
docker compose exec web python manage.py check
docker compose exec web python manage.py test
```

Health check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health/
```

Expected response:

```json
{"status":"ok"}
```

## Cloudflare Tunnel deployment

The public deployment uses one remotely managed Cloudflare Tunnel with two
published applications:

| Public hostname | Service URL inside Docker |
| --- | --- |
| `api.carebridge-lab.com` | `http://web:8000` |
| `storage.carebridge-lab.com` | `http://minio:9000` |

Both routes are required. The iOS app talks to the API hostname, while
presigned photo and document URLs point directly to the storage hostname.

Set these values in `backend/.env`:

```env
DJANGO_ENV=production
DJANGO_DEBUG=False
ALLOWED_HOSTS=api.carebridge-lab.com,localhost,127.0.0.1
SECURE_SSL_REDIRECT=True
CLOUDFLARE_TUNNEL_TOKEN=replace-with-the-tunnel-token
AWS_S3_PUBLIC_ENDPOINT_URL=https://storage.carebridge-lab.com
```

Start the public stack with:

```bash
cd backend/docker
docker compose --env-file ../.env \
  -f docker-compose.yml \
  -f docker-compose.tunnel.yml \
  up -d --build
```

Debug iOS builds continue using the private device endpoint. Release builds
automatically use `https://api.carebridge-lab.com`.

## Main Backend Capabilities

- JWT authentication, user profile, family groups, and family membership.
- Chat rooms, REST messages, WebSocket delivery, and dynamic translation fields.
- Board requests, leave requests, calendar events, todos, care logs, and medication confirmations.
- HealthKit / Apple Watch data ingestion, thresholds, alerts, weekly steps, and health WebSocket broadcast.
- Receipt and document upload through S3 / MinIO quarantine keys, Celery de-identification, and processed presigned URLs.
- OpenAI-backed AI assistant, care analysis, handover report generation, subsidy form support, first-aid RAG, and SSE streaming.
- SOS trigger/history/resolve and APNs-backed notification infrastructure.
- Staff-only admin API for dashboard, storage, table, request-log, and runtime-log inspection.

## Documentation

Formal development documents for source submission are kept in `Doc/`:

- `Doc/PRD.md`
- `Doc/Architecture_Plan.md`
- `Doc/API_Documentation.md`
- `Doc/Backend_Implementation_Gap_Report.md`

Local exploratory notes, generated diagrams, and old handoff checklists should not be kept as top-level Markdown files.

## Environment

Use `backend/.env.example` as the backend environment template. Do not commit real credentials, API keys, APNs credentials, DLP service account JSON, S3 credentials, or personal health data.

When Google DLP is enabled in Docker, the credential file must be mounted into both `web` and `celery-worker`, usually through:

```env
GOOGLE_APPLICATION_CREDENTIALS=/secrets/carebridge-dlp.json
```

## Notes

CareBridge is a competition and prototype system. AI-generated emergency, first-aid, and health content must not replace professional medical judgment.
