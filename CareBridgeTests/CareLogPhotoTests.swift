import Foundation
import Testing
@testable import CareBridge

struct CareLogPhotoTests {
    @Test func decodesPresignedPhotoURL() throws {
        let json = """
        {
          "id": "8D4B903B-A316-4F0D-A55E-4EB444A9D31A",
          "type": "meal",
          "content": {"description": "午餐"},
          "timestamp": "2026-06-21T12:30:00Z",
          "photo_url": "https://example.com/care-photo.jpg"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let entry = try decoder.decode(
            CareLogEntry.self,
            from: Data(json.utf8)
        )

        #expect(entry.hasPhoto)
        #expect(
            entry.photoURL?.absoluteString
                == "https://example.com/care-photo.jpg"
        )
    }

    @Test func encodesStorageKeyInsteadOfDownloadURL() throws {
        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: .activity,
            title: "散步",
            detail: "30分鐘",
            timestamp: Date(timeIntervalSince1970: 0),
            hasPhoto: true,
            photoURL: URL(string: "https://example.com/temporary.jpg"),
            photoKey: "care-logs/family-1/photos/photo.jpg"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(entry))
                as? [String: Any]
        )

        #expect(
            object["photo_key"] as? String
                == "care-logs/family-1/photos/photo.jpg"
        )
        #expect(object["photo_url"] == nil)
    }
}
