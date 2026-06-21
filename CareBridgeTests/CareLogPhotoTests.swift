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
        #expect(entry.title == "午餐")
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
        let content = try #require(object["content"] as? [String: Any])
        #expect(content["title"] as? String == "散步")
    }

    @Test func decodesUserEnteredMealAndActivityTitles() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let mealJSON = """
        {
          "id": "meal-1",
          "type": "meal",
          "content": {
            "title": "地瓜粥",
            "description": "早餐｜食慾：良好"
          },
          "timestamp": "2026-06-22T08:00:00Z"
        }
        """
        let activityJSON = """
        {
          "id": "activity-1",
          "type": "activity",
          "content": {
            "title": "公園散步",
            "note": "30分鐘｜輕度"
          },
          "timestamp": "2026-06-22T09:00:00Z"
        }
        """

        let meal = try decoder.decode(
            CareLogEntry.self,
            from: Data(mealJSON.utf8)
        )
        let activity = try decoder.decode(
            CareLogEntry.self,
            from: Data(activityJSON.utf8)
        )

        #expect(meal.title == "地瓜粥")
        #expect(meal.detail == "早餐｜食慾：良好")
        #expect(activity.title == "公園散步")
        #expect(activity.detail == "30分鐘｜輕度")
    }
}
