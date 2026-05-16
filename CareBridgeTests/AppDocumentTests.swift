import Foundation
import Testing
@testable import CareBridge

struct AppDocumentTests {
    @Test func decodesBackendFileURLForRemotePreview() throws {
        let json = Data("""
        {
          "id": "doc-1",
          "title": "Health report",
          "category": "medical",
          "file_url": "https://api.carebridge-lab.com/document.pdf",
          "file_size": 2048,
          "created_at": "2026-05-16T00:00:00Z",
          "deid_status": "completed"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let document = try decoder.decode(AppDocument.self, from: json)

        #expect(document.remoteURL == URL(string: "https://api.carebridge-lab.com/document.pdf"))
        #expect(document.previewURL == document.remoteURL)
        #expect(document.localURL == nil)
        #expect(document.fileSize == "2 KB")
    }
}
