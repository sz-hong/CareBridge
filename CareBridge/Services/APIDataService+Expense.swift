import Foundation
import UIKit

extension APIDataService {
    // MARK: - Expenses
    func fetchExpenses(month: Date?) async throws -> [Expense] { try await get(path: APIEndpoint.expenses) }
    /// Hit the detail endpoint so the backend resolves a fresh presigned
    /// image URL for this one expense — list responses no longer include it.
    func fetchExpense(id: String) async throws -> Expense {
        try await get(path: APIEndpoint.expense(id: id))
    }
    func fetchSpendingSummary(month: Date?) async throws -> SpendingSummary { try await get(path: APIEndpoint.expenseMonthly) }
    func createExpense(_ expense: Expense) async throws -> Expense { try await post(path: APIEndpoint.expenses, body: expense) }
    func updateExpense(_ expense: Expense) async throws -> Expense { try await patch(path: APIEndpoint.expense(id: expense.id), body: expense) }
    func deleteExpense(id: String) async throws { try await delete(path: APIEndpoint.expense(id: id)) }

    /// Redact obvious local PII, upload to quarantine storage, and return the
    /// backend raw key for the de-identification pipeline.
    func uploadReceiptImage(_ image: UIImage) async throws -> ReceiptUploadReference {
        struct UploadURLResponse: Codable {
            let uploadId: String
            let uploadUrl: String
            let rawKey: String
        }

        let info: UploadURLResponse = try await post(
            path: APIEndpoint.expenseUploadURL,
            body: ["content_type": "image/jpeg"]
        )
        let redacted = try await privacyRedactionService.redactImageForUpload(image)

        guard let putURL = URL(string: info.uploadUrl) else { throw URLError(.badURL) }
        var putReq = URLRequest(url: putURL)
        putReq.httpMethod = "PUT"
        putReq.setValue(redacted.mimeType, forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.upload(for: putReq, from: redacted.data)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw APIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return ReceiptUploadReference(uploadId: info.uploadId, rawKey: info.rawKey)
    }
}
