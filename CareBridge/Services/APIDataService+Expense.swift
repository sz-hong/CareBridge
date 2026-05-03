import Foundation
import UIKit

extension APIDataService {
    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { try await get(path: APIEndpoint.expenses) }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary { try await get(path: APIEndpoint.expenseMonthly) }
    func createExpense(_ expense: Expense) async throws -> Expense { try await post(path: APIEndpoint.expenses, body: expense) }

    /// Request a presigned PUT URL from the backend, upload the JPEG bytes directly
    /// to object storage, then return the bare `image_url` to send back with the
    /// expense POST. Throws on encode/upload failure.
    func uploadReceiptImage(_ image: UIImage) async throws -> String {
        struct UploadURLResponse: Codable { let uploadUrl: String; let imageUrl: String }

        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw APIError.emptyResponse
        }

        let info: UploadURLResponse = try await post(
            path: APIEndpoint.expenseUploadURL,
            body: ["content_type": "image/jpeg"]
        )

        guard let putURL = URL(string: info.uploadUrl) else { throw URLError(.badURL) }
        var putReq = URLRequest(url: putURL)
        putReq.httpMethod = "PUT"
        putReq.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: putReq, from: data)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return info.imageUrl
    }
}
