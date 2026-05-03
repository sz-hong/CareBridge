import Foundation

extension APIDataService {
    // MARK: - Leave
    func fetchLeaveRequests() async throws -> [LeaveRequest] { try await get(path: APIEndpoint.leaves) }
    func createLeaveRequest(_ request: LeaveRequest) async throws -> LeaveRequest { try await post(path: APIEndpoint.leaves, body: request) }
    func updateLeaveStatus(id: String, status: LeaveStatus) async throws -> LeaveRequest {
        try await patch(path: APIEndpoint.leaveStatus(id: id), body: ["status": status.rawValue])
    }
    func voteLeave(id: String, isAvailable: Bool) async throws -> LeaveRequest {
        try await post(path: APIEndpoint.leaveVote(id: id), body: ["is_available": isAvailable])
    }
}
