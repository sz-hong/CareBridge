# CareBridge docker_test

This folder is for frontend-only local runs when the real Django backend is not running or when frontend work needs a stable mock API.

It is intentionally separate from `backend/docker/`. Do not edit the shared backend compose files for frontend-only startup needs.

## Start the mock API

Default mode uses `127.0.0.1:8001` so it can run without conflicting with the real backend on `8000`.

```powershell
cd C:\CareBridge\docker_test
docker compose up -d
```

Health check:

```powershell
curl http://127.0.0.1:8001/api/v1/health/
```

## Use port 8000 when the backend is stopped

If the frontend expects the normal backend URL and Django is not running, start the mock API on port `8000`:

```powershell
cd C:\CareBridge\docker_test
$env:CAREBRIDGE_MOCK_API_PORT = "8000"
docker compose up -d
```

Stop it before starting the real backend again:

```powershell
docker compose down
```

## Dashboard dev server

When running the dashboard through Vite, point it at the mock API:

```powershell
cd C:\CareBridge\dashboard
$env:VITE_API_BASE_URL = "http://127.0.0.1:8001/api/v1"
npm run dev
```

Login accepts any email/password. A convenient account is:

```text
email: frontend@carebridge.test
password: anything
```

The mock user is returned with `is_staff: true`, so the dashboard admin pages can load.

## iOS simulator

For simulator testing, either run the mock API on `8000`, or temporarily point the debug base URL at `http://127.0.0.1:8001/api/v1`.

For physical device testing, use the Mac LAN/Tailscale IP with the selected mock port, for example:

```text
http://<mac-ip>:8001/api/v1
```

## Supported mock endpoints

- `GET /api/v1/health/`
- `POST /api/v1/auth/login/`
- `POST /api/v1/auth/token/`
- `POST /api/v1/auth/token/refresh/`
- `GET /api/v1/auth/me/`
- Dashboard admin endpoints under `/api/v1/admin/` for overview, tables, CRUD smoke tests, request logs, runtime logs, audit logs, and storage lists.

Other `/api/v1/*` paths return simple success mock payloads. This is for frontend startup and smoke testing only; backend integration testing must still use `backend/docker/`.

## Local-only customization

Use ignored local files for personal variants:

- `docker-compose.local.yml`
- `docker-compose.override.yml`
- `.env`
- `logs/`