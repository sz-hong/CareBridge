import Foundation
import Testing
@testable import CareBridge

struct TodoItemTests {
    @Test func encodesAssigneeIDForBackendCreateContract() throws {
        let assigneeID = "11111111-1111-1111-1111-111111111111"
        let todo = TodoItem(
            id: "local-id",
            title: "Call clinic",
            assignee: "Caregiver",
            priority: .high,
            dueDate: nil,
            isCompleted: false,
            assigneeId: assigneeID
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data = try encoder.encode(todo)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["assignee_id"] as? String == assigneeID)
        #expect(json["status"] as? String == "pending")
    }
}
