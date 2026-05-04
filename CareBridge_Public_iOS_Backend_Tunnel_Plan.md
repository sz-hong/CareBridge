# CareBridge iOS Public Backend Tunnel Plan

This document describes the technical plan for letting the CareBridge iOS app
connect to a Django backend running on this computer through a public Cloudflare
Tunnel.

## 0. Fixed Domain Choice

Use `carebridge-lab.com` as the fixed project domain for this tunnel setup.

Subdomains:

- `api.carebridge-lab.com` for Django REST and WebSocket traffic.
- `storage.carebridge-lab.com` for local MinIO/S3 presigned URLs.

Rationale:

- Keeps the CareBridge project name visible.
- `lab` makes the domain clearly development/testing oriented, so it is less
  likely to be confused with a future production or public brand domain.
- Uses only ASCII characters, which fits Cloudflare Registrar requirements.

Before purchase, confirm final availability in Cloudflare Registrar. If
`carebridge-lab.com` is not available at checkout time, use
`carebridge-devlab.com` as the fallback and update this document consistently.

## 1. Confirmed Current State

- The backend is Django 5 + Django REST Framework + Django Channels.
- The ASGI entrypoint is `backend/carebridge_api/asgi.py`.
- REST APIs are mounted under `/api/v1/`.
- Chat WebSocket traffic is routed through `/ws/chat/<chat_id>/`.
- `backend/carebridge_api/settings/production.py` now sets
  `SECURE_PROXY_SSL_HEADER` so Django recognizes HTTPS requests forwarded by
  Cloudflare Tunnel.
- `CareBridge/Services/AppConfig.swift` now defaults to the public Cloudflare
  Tunnel endpoint and keeps simulator/device fallback modes.
- `CareBridge/Info.plist` contains HTTP App Transport Security exceptions for
  local development IPs. A public HTTPS Cloudflare hostname should not need a new
  ATS exception.
- A Cloudflare Tunnel named `carebridge-local` has been created and its Windows
  connector is healthy.
- Docker Desktop is installed. Some shells may still need the full Docker CLI
  path if `docker` is not yet in PATH.
- The existing backend `.venv` was created with Python 3.13. A previous
  `manage.py check` attempt failed inside the Daphne/Twisted dependency chain,
  so backend validation should use Docker or a Python 3.12 virtual environment.
- The existing `backend/.venv312/python.exe` environment uses Python 3.12 and
  passed `manage.py check`.
- Receipt image upload uses MinIO/S3 presigned URLs. If the backend generates
  URLs with `http://localhost:9000`, an iPhone outside this computer cannot use
  them.

## 2. Current Validation Status

Validated on 2026-05-04:

- Cloudflare Tunnel connector status: healthy.
- Published application route:
  `api.carebridge-lab.com` -> `http://localhost:8000`.
- Published application route:
  `storage.carebridge-lab.com` -> `http://localhost:9000`.
- Local Django health check:
  `http://127.0.0.1:8000/api/v1/health/` returned `{"status":"ok"}`.
- Public API health check:
  `https://api.carebridge-lab.com/api/v1/health/` returned
  `{"status":"ok"}`.
- Public authenticated REST smoke test passed for the iOS core API surface:
  login, token refresh, auth profile, family, members, health dashboard, weekly
  steps, chats, care logs, medications, expenses, todos, events, leaves,
  documents, notifications, and board.
- Public WebSocket smoke test passed for
  `wss://api.carebridge-lab.com/ws/chat/<chat_id>/?token=<jwt>`.
- Public storage health check passed through
  `https://storage.carebridge-lab.com/minio/health/live`.
- Expense upload URL smoke test returned public URLs under
  `https://storage.carebridge-lab.com/`.
- A presigned PUT upload to `https://storage.carebridge-lab.com/...` returned
  HTTP 200.
- Docker container validation passed:
  - `python manage.py test` with `DJANGO_ENV=development`
  - `python manage.py makemigrations --check --dry-run`
  - `python manage.py check` with production settings

Not yet validated:

- iOS runtime validation on simulator or device. This Windows environment does
  not provide `xcodebuild` or `xcrun`; run the Xcode command in the validation
  section from a Mac.
- The AI SSE frontend flow. The backend streaming route is separate from the
  Cloudflare tunnel setup and still needs a contract check with the Swift
  `streamAIResponse` implementation.

## 3. Target Architecture

```text
iPhone App
  -> https://api.carebridge-lab.com/api/v1/...
  -> wss://api.carebridge-lab.com/ws/chat/...
  -> Cloudflare Tunnel
  -> cloudflared on Windows
  -> http://127.0.0.1:8000
  -> Django ASGI backend
```

If local MinIO must also be reachable by the iPhone:

```text
iPhone App
  -> https://storage.carebridge-lab.com/<bucket>/<object>
  -> Cloudflare Tunnel
  -> http://127.0.0.1:9000
  -> MinIO S3 API
```

## 4. Cloudflare Tunnel Plan

- Use a named Cloudflare Tunnel, not a temporary `trycloudflare.com` quick
  tunnel. The app needs a stable hostname, and the backend includes streaming
  behavior.
- Publish these routes:
  - `api.carebridge-lab.com` -> `http://localhost:8000`
  - `storage.carebridge-lab.com` -> `http://localhost:9000` if using local MinIO
- Do not enable Cloudflare Access on the API route unless the iOS app is also
  updated to send Cloudflare Access service credentials. The current app
  authenticates with backend JWT tokens.
- Add cache bypass rules for API and storage hostnames. API responses, SSE, and
  presigned URLs should not be cached by Cloudflare.
- Keep Cloudflare tunnel tokens and credentials outside git.

## 5. Django Settings Plan

Implemented in `backend/carebridge_api/settings/production.py`:

```python
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

Use production-like environment settings for public tunnel testing:

```env
DJANGO_ENV=production
DJANGO_DEBUG=False
ALLOWED_HOSTS=api.carebridge-lab.com,localhost,127.0.0.1
SECURE_SSL_REDIRECT=True
```

Notes:

- Do not expose `DJANGO_ENV=development` publicly. It currently uses permissive
  development settings such as wildcard hosts and open CORS.
- CORS is not required for the native iOS app because `URLSession` is not bound
  by browser same-origin policy.
- If a browser frontend is added later, add that frontend origin to
  `CORS_ALLOWED_ORIGINS`.
- `CSRF_TRUSTED_ORIGINS` is not the main requirement for the JWT-based native
  iOS API. Add it later only if browser cross-origin unsafe requests or
  cross-domain Django forms are introduced.

## 6. Storage / MinIO Plan

If continuing to use local MinIO for public iPhone testing, configure the
backend to generate presigned URLs with the public storage hostname:

```env
AWS_S3_ENDPOINT_URL=https://storage.carebridge-lab.com
AWS_STORAGE_BUCKET_NAME=carebridge-storage
```

Do not generate a presigned URL for `localhost:9000` and rewrite the hostname
afterward. The hostname is part of the S3 signature, so rewriting can invalidate
the URL.

If using real AWS S3 instead of local MinIO:

- Leave `AWS_S3_ENDPOINT_URL` blank.
- Do not create the `storage.carebridge-lab.com` tunnel route.

## 7. iOS Settings Plan

Implemented in `CareBridge/Services/AppConfig.swift` with public tunnel as the
default mode:

```swift
enum Mode {
    case simulator
    case device
    case publicTunnel
}
```

The public tunnel mode should use:

```swift
static let publicHost = "api.carebridge-lab.com"

static var scheme: String {
    mode == .publicTunnel ? "https" : "http"
}

static var wsScheme: String {
    mode == .publicTunnel ? "wss" : "ws"
}
```

The derived URLs should remain:

```swift
static var apiBaseURL: String { "\(scheme)://\(host)/api/v1" }
static var wsBaseURL: String { "\(wsScheme)://\(host)/ws" }
```

`Info.plist` should not need a new ATS exception for the public Cloudflare
hostname because the public route should be HTTPS with a valid certificate.
Existing HTTP ATS exceptions should be treated as local development exceptions.

## 8. Local Runtime Plan

Preferred local runtime:

- Install Docker Desktop.
- Use the existing backend Dockerfile and Compose stack because it targets
  Python 3.12 and already includes PostgreSQL, Redis, and MinIO.

If using Docker Compose, bind published ports to loopback only:

```yaml
ports:
  - "127.0.0.1:8000:8000"
```

Apply the same loopback binding to PostgreSQL, Redis, MinIO API, and MinIO
console ports where external LAN access is not needed. This is now reflected in
`backend/docker/docker-compose.yml`.

Alternative local runtime:

- Rebuild the virtual environment with Python 3.12.
- Install PostgreSQL and Redis separately.
- Run the ASGI server locally:

```powershell
uvicorn carebridge_api.asgi:application --host 127.0.0.1 --port 8000
```

## 9. Validation Checklist

Local health check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health/
```

Public health check:

```powershell
Invoke-RestMethod https://api.carebridge-lab.com/api/v1/health/
```

Redirect check:

```powershell
curl.exe -I https://api.carebridge-lab.com/api/v1/health/
```

iPhone mobile-network checks:

- Login.
- Token refresh.
- Authenticated REST API requests.
- Chat WebSocket:
  `wss://api.carebridge-lab.com/ws/chat/<chat_id>/?token=<jwt>`.
- Receipt image upload with a presigned PUT URL that starts with
  `https://storage.carebridge-lab.com/`.

AI SSE note:

- The backend streaming endpoint is enabled with `?stream=true`.
- The current Swift `streamAIResponse` path should be checked separately because
  it does not appear to append `?stream=true`, and the frontend/backend SSE
  payload field names may not currently match. That is a separate app behavior
  issue, not a Cloudflare Tunnel issue.

iOS unit tests on a Mac with Xcode:

```bash
xcodebuild test -project CareBridge.xcodeproj -scheme CareBridge -destination 'platform=iOS Simulator,name=<device>'
```

## 10. Troubleshooting

- Cloudflare `1016`: DNS route exists, but the tunnel is not running or not
  associated correctly.
- Django `DisallowedHost`: add the public API hostname to `ALLOWED_HOSTS`.
- Repeated HTTP 301/302 redirects: verify `SECURE_PROXY_SSL_HEADER` and
  Cloudflare's `X-Forwarded-Proto` behavior.
- iPhone cannot upload receipt image: verify the presigned URL uses
  `https://storage.carebridge-lab.com/`, not `localhost:9000`.
- WebSocket fails but REST works: verify Cloudflare WebSocket support is enabled
  and the iOS URL uses `wss://`.

## 11. References

- [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/)
- [Cloudflare Tunnel routing](https://developers.cloudflare.com/tunnel/routing/)
- [Cloudflare Tunnel setup](https://developers.cloudflare.com/tunnel/setup/)
- [Cloudflare WebSockets](https://developers.cloudflare.com/network/websockets/)
- [Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)
- [Django settings](https://docs.djangoproject.com/en/dev/ref/settings/)
- [Django CSRF trusted origins](https://docs.djangoproject.com/en/4.2/ref/settings/#csrf-trusted-origins)
- [Apple App Transport Security](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)
- [django-cors-headers](https://github.com/adamchainz/django-cors-headers)
