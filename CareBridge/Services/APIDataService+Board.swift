import Foundation

extension APIDataService {
    // MARK: - Purchase Requests
    func fetchPurchaseRequests() async throws -> [PurchaseRequest] { try await get(path: APIEndpoint.board) }
    func createPurchaseRequest(_ request: PurchaseRequest) async throws -> PurchaseRequest { try await post(path: APIEndpoint.board, body: request) }
    func updatePurchaseRequestStatus(id: String, status: String) async throws -> PurchaseRequest {
        try await patch(path: APIEndpoint.boardStatus(id: id), body: ["status": status])
    }
}
