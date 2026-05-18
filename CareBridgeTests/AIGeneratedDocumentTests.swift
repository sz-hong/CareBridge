import Foundation
import Testing
@testable import CareBridge

struct AIGeneratedDocumentTests {
    @Test func generatedDocumentRemovesCommonMarkdownSyntax() {
        let document = AIGeneratedDocument(
            title: "交班報告",
            kind: .handoverReport,
            body: """
            ## Summary
            - **Amlodipine 5mg** after meals
            `raw note`
            [care plan](https://example.com)
            """
        )

        #expect(document.body.contains("Summary"))
        #expect(document.body.contains("Amlodipine 5mg after meals"))
        #expect(document.body.contains("raw note"))
        #expect(document.body.contains("care plan"))
        #expect(!document.body.contains("##"))
        #expect(!document.body.contains("**"))
        #expect(!document.body.contains("`"))
        #expect(!document.body.contains("](https://example.com)"))
    }

    @Test func subsidyFormResponseBuildsPlainTextDocument() {
        let response = AISubsidyFormResponse(
            formType: "long_term_care",
            formFields: [
                "applicant": "Grandma Wu",
                "days": "30"
            ],
            tokensUsed: 10
        )

        let document = AIGeneratedDocument.subsidyForm(response)

        #expect(document.title == "補助表單")
        #expect(document.kind == .subsidyForm)
        #expect(document.body.contains("applicant: Grandma Wu"))
        #expect(document.body.contains("days: 30"))
        #expect(document.plainText.contains("補助表單"))
        #expect(document.fileName.hasSuffix(".txt"))
        #expect(!document.plainText.contains("**"))
        #expect(!document.plainText.contains("```"))
    }
}
