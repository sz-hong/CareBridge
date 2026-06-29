import Foundation
import Testing
@testable import CareBridge

struct ExpenseRecordPermissionsTests {
    @Test func familyCanManageFinanceRecords() {
        #expect(ExpenseRecordPermissions.canManageRecords(userRole: .family))
    }

    @Test func caregiverAndElderCannotManageFinanceRecords() {
        #expect(!ExpenseRecordPermissions.canManageRecords(userRole: .caregiver))
        #expect(!ExpenseRecordPermissions.canManageRecords(userRole: .elder))
    }

    @Test func doesNotEncodePresignedImageURLBackToExpenseAPI() throws {
        let expense = Expense(
            id: "expense-1",
            title: "Pharmacy",
            amount: 120,
            category: "medical",
            date: Date(timeIntervalSince1970: 0),
            hasReceipt: true,
            imageUrl: "https://download.example/presigned.jpg"
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data = try encoder.encode(expense)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["image_url"] == nil)
        #expect(json["raw_image_key"] == nil)
    }

    @Test func recentTransactionPreviewIsLimitedToTenRows() {
        let expenses = (0..<12).map { index in
            Expense(
                id: "expense-\(index)",
                title: "Expense \(index)",
                amount: Double(index),
                category: "other",
                date: Date(timeIntervalSince1970: Double(index)),
                hasReceipt: false
            )
        }

        let preview = ExpenseRecordPresentation.recentTransactions(from: expenses)

        #expect(preview.count == 10)
        #expect(preview.map(\.id) == expenses.prefix(10).map(\.id))
    }

    @Test func recentTransactionDetailDoesNotAllowManagement() {
        #expect(ExpenseRecordPermissions.canManageRecords(userRole: .family, context: .allExpenses))
        #expect(!ExpenseRecordPermissions.canManageRecords(userRole: .family, context: .recentTransactions))
    }

}
