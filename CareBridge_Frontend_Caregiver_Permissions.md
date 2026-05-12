# Caregiver Permission Frontend Handoff

This note describes the frontend changes needed after the backend caregiver
permission update.

## Backend Behavior

The backend now treats `user.role == "caregiver"` as a restricted role.

Caregivers receive `403 permission_denied` for:

- Every `DELETE` endpoint.
- All document management endpoints:
  - `GET /api/v1/documents/`
  - `GET /api/v1/documents/{id}/`
  - `POST /api/v1/documents/upload-url/`
  - `POST /api/v1/documents/`
  - `DELETE /api/v1/documents/{id}/`
- Medication setting writes:
  - `POST /api/v1/medications/`
  - `PUT /api/v1/medications/{id}/`
  - `PATCH /api/v1/medications/{id}/`
  - `DELETE /api/v1/medications/{id}/`

Caregivers can still use:

- `GET /api/v1/medications/`
- `GET /api/v1/medications/{id}/`
- `GET /api/v1/medications/today_confirmations/`
- `POST /api/v1/medications/{id}/confirm/`
- Existing AI endpoints under `/api/v1/ai/`

## Required SwiftUI Updates

Use the current user's role from `UserProfile.role`.

For caregivers:

- Hide or disable the document management entry in `MoreView`.
- Do not render `DocumentsView` as a reachable route.
- Do not call `fetchDocuments()`, `uploadDocument(...)`, or `deleteDocument(id:)`.
- Keep medication list and medication confirmation available.
- Keep the add/edit medication UI hidden or disabled.
- Hide destructive controls that call backend `DELETE` APIs.

For family members:

- Keep the existing document management flow available.
- Keep medication creation and editing available.
- Keep existing delete flows available.

## API Error Handling

Treat `403 permission_denied` as an authorization error, not an auth-session error.

Do not clear tokens or send the user back to login for a 403 response. Show a
permission message such as:

```text
You do not have permission to perform this action.
```

Continue using token refresh only for `401` responses.

## Suggested Acceptance Checks

Verify these scenarios from the iOS app:

- Caregiver login does not show the document management entry.
- Caregiver cannot navigate to document upload or document list screens.
- Caregiver can open medication list.
- Caregiver can confirm a scheduled medication dose.
- Caregiver cannot access add/edit medication controls.
- Caregiver delete actions either are hidden or show a permission message.
- Family member login still shows documents, upload, medication management, and delete flows.
- A backend `403 permission_denied` does not log the user out.

## AI Notes

No frontend AI changes are required for this backend update.

The backend still allows caregivers to call the existing AI endpoints. The AI
assistant currently does not expose document management data through its tools.
If a future AI feature reads document records, add a matching caregiver check so
caregivers cannot access documents indirectly through AI.
