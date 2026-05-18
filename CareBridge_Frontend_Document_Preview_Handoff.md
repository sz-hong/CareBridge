# CareBridge Document Preview Handoff

## Goal

Make document preview stable in the iOS app by previewing a local cached file, not the remote processed URL directly.

The backend now exposes only processed document URLs through `file_url`. The app must keep that privacy boundary: preview can use processed URLs only, and it must never fall back to a quarantine/raw upload URL.

## Current Issue

`CareBridge/Views/Document/DocumentsView.swift` currently passes `AppDocument.previewURL` directly into `.quickLookPreview`.

That URL is a remote presigned storage URL. QuickLook can be unreliable with remote presigned URLs. A common failure mode is that the preview sheet opens but only shows the file name instead of rendering the image, PDF, or text file.

Backend storage checks showed processed image URLs can be downloaded with normal `GET`, `HEAD`, and `Range` requests. The remaining frontend fix is to download the processed file first and give QuickLook a local `file://` URL.

## Required Frontend Behavior

- Preview is enabled only when `AppDocument.previewURL` is non-nil.
- `processing` and `pending` documents remain disabled.
- `failed` documents remain disabled.
- `needs_review` documents may preview if the backend returned a processed `file_url`.
- On preview tap, download the processed URL with `URLSession`.
- Save the downloaded bytes to a local temp/cache file.
- Preserve a useful extension: `.png`, `.jpg`, `.jpeg`, `.pdf`, or `.txt`.
- Pass the local file URL to `.quickLookPreview`.
- If download fails, show a user-visible error and do not open QuickLook.
- Do not use `localURL` from the original upload as a fallback.

## Suggested Implementation

Update `DocumentsView` state:

```swift
@State private var previewLocalURL: URL?
@State private var previewLoadingDocumentID: String?
@State private var previewError: String?
```

Change the preview action from a direct assignment:

```swift
if let url = doc.previewURL {
    previewURL = url
}
```

to an async preparation step:

```swift
Task {
    await preparePreview(for: doc)
}
```

Keep QuickLook bound to the local URL:

```swift
.quickLookPreview($previewLocalURL)
```

Add a helper with this behavior:

```swift
@MainActor
private func preparePreview(for document: AppDocument) async {
    guard let remoteURL = document.previewURL else { return }
    previewLoadingDocumentID = document.id
    previewError = nil
    defer { previewLoadingDocumentID = nil }

    do {
        let localURL = try await downloadPreviewFile(
            remoteURL: remoteURL,
            documentID: document.id
        )
        previewLocalURL = localURL
    } catch {
        previewError = "Unable to load preview. Please try again."
    }
}
```

The download helper can live in `DocumentsView` first. Move it to a small service only if another screen needs it.

```swift
private func downloadPreviewFile(remoteURL: URL, documentID: String) async throws -> URL {
    let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)

    guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
        throw URLError(.badServerResponse)
    }

    let contentType = http.value(forHTTPHeaderField: "Content-Type")
    let fileExtension = previewFileExtension(remoteURL: remoteURL, contentType: contentType)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CareBridgePreviews", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )

    let destination = directory.appendingPathComponent("\(documentID).\(fileExtension)")
    if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporaryURL, to: destination)
    return destination
}
```

Recommended extension mapping:

```swift
private func previewFileExtension(remoteURL: URL, contentType: String?) -> String {
    let pathExtension = remoteURL.pathExtension.lowercased()
    if ["png", "jpg", "jpeg", "pdf", "txt"].contains(pathExtension) {
        return pathExtension
    }

    switch contentType?.lowercased().split(separator: ";").first {
    case "image/png":
        return "png"
    case "image/jpeg":
        return "jpg"
    case "application/pdf":
        return "pdf"
    case "text/plain":
        return "txt"
    default:
        return "dat"
    }
}
```

## UI Details

- While a row is downloading, disable that row's preview button.
- Show a small `ProgressView` or replace the eye icon while `previewLoadingDocumentID == document.id`.
- Keep the current DLP status badge behavior:
  - `processing` / `pending`: disabled
  - `failed`: disabled
  - `completed`: enabled when processed URL exists
  - `needs_review`: enabled when processed URL exists
- Show `previewError` with an alert or existing app toast pattern.
- Clear temp preview files in `.onDisappear` or on app launch if needed. It is acceptable to overwrite the same `document.id` file on every preview tap.

## Backend Contract

The document API returns `file_url` only for processed outputs. The processed output may be:

- `image/png` or `image/jpeg` for image uploads
- `text/plain` for PDF metadata-only previews
- legacy seeded PDF/image URLs for demo data

Frontend must treat `file_url` as the only preview source. Do not use `raw_file_key`, quarantine URLs, or upload-local file URLs for preview.

## Tests

Add focused tests where practical:

- `AppDocument` keeps preview disabled for `processing`, `pending`, and `failed`.
- `AppDocument` allows preview for `completed` and `needs_review` when `remoteURL` exists.
- Preview download helper maps MIME types to correct file extensions.
- Preview download helper writes a local file and returns a `file://` URL.
- Failed HTTP response does not set `previewLocalURL` and shows an error.

Manual QA:

- Upload PNG and preview after processing completes.
- Upload JPEG and preview after processing completes.
- Upload PDF and preview processed `.txt` output.
- Verify `needs_review` with processed URL can preview.
- Verify failed documents keep the preview button disabled.
- Turn network off before tapping preview and confirm the app shows an error instead of opening a blank QuickLook sheet.

## Acceptance Criteria

- QuickLook receives only local file URLs.
- Processed PNG/JPEG previews render as images.
- Processed PDF text previews render as readable text.
- The app never previews raw quarantine files.
- Failed preview downloads show an error and leave the document list usable.
