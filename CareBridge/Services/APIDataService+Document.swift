import Foundation

extension APIDataService {
    // MARK: - Documents
    func fetchDocuments() async throws -> [AppDocument] { try await get(path: APIEndpoint.documents) }

    /// Upload document bytes to quarantine storage, then create metadata that
    /// the backend DLP pipeline will publish after redaction.
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument {
        struct UploadURLResponse: Codable {
            let uploadUrl: String
            let rawKey: String
        }

        let mimeType = Self.detectDocumentMimeType(fileData)
        let sanitizedData = try privacyRedactionService.stripMetadata(
            from: fileData,
            mimeType: mimeType
        )
        let uploadInfo: UploadURLResponse = try await post(
            path: APIEndpoint.documentUploadURL,
            body: [
                "content_type": AnyEncodable(mimeType),
                "file_size": AnyEncodable(sanitizedData.count),
                "filename": AnyEncodable(title),
            ]
        )

        guard let putURL = URL(string: uploadInfo.uploadUrl) else { throw URLError(.badURL) }
        var putReq = URLRequest(url: putURL)
        putReq.httpMethod = "PUT"
        putReq.setValue(mimeType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: putReq, from: sanitizedData)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let body: [String: AnyEncodable] = [
            "title": AnyEncodable(title),
            "category": AnyEncodable(category),
            "raw_file_key": AnyEncodable(uploadInfo.rawKey),
            "file_size": AnyEncodable(sanitizedData.count),
            "mime_type": AnyEncodable(mimeType),
        ]
        return try await post(path: APIEndpoint.documents, body: body)
    }

    func deleteDocument(id: String) async throws { try await delete(path: APIEndpoint.document(id: id)) }

    /// Approve a document flagged `needs_review`; the backend flips it to
    /// `completed` and records the reviewer, returning the updated document.
    func approveDocument(id: String) async throws -> AppDocument {
        try await post(path: APIEndpoint.documentApprove(id: id))
    }

    private static func detectDocumentMimeType(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return "application/octet-stream"
    }
}
