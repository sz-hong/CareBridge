import Foundation

extension APIDataService {
    // MARK: - Documents
    func fetchDocuments() async throws -> [AppDocument] { try await get(path: APIEndpoint.documents) }
    /// Backend CreateDocumentSerializer requires `file_url, file_size, mime_type`.
    /// Caller must upload bytes to object storage first and supply the resulting URL.
    /// Until that flow exists, we send placeholders to avoid 400s on empty required fields.
    func uploadDocument(title: String, category: String, fileData: Data) async throws -> AppDocument {
        let body: [String: AnyEncodable] = [
            "title":     AnyEncodable(title),
            "category":  AnyEncodable(category),
            "file_url":  AnyEncodable(""),
            "file_size": AnyEncodable(fileData.count),
            "mime_type": AnyEncodable("application/octet-stream"),
        ]
        return try await post(path: APIEndpoint.documents, body: body)
    }
    func deleteDocument(id: String) async throws { try await delete(path: APIEndpoint.document(id: id)) }
}
