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

    @Test func processingDocumentDoesNotExposeLocalRawPreview() {
        let localURL = URL(fileURLWithPath: "/tmp/raw-report.pdf")
        let document = AppDocument(
            id: "doc-processing",
            title: "Processing report",
            category: "medical",
            fileSize: "2 KB",
            uploadDate: Date(),
            localURL: localURL,
            remoteURL: nil,
            deidStatus: "processing"
        )

        #expect(document.previewURL == nil)
        #expect(document.isAwaitingDeidentification)
    }

    @Test func reviewedProcessedDocumentCanPreviewRemoteURL() {
        let remoteURL = URL(string: "https://api.carebridge-lab.com/processed.pdf")
        let document = AppDocument(
            id: "doc-reviewed",
            title: "Reviewed report",
            category: "medical",
            fileSize: "2 KB",
            uploadDate: Date(),
            remoteURL: remoteURL,
            deidStatus: "needs_review"
        )

        #expect(document.previewURL == remoteURL)
        #expect(!document.isAwaitingDeidentification)
    }
}
