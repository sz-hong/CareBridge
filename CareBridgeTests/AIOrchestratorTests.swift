import Foundation
import Testing
@testable import CareBridge

private enum LocalAIStubError: Error {
    case generationFailed
}

private final class LocalAIStub: LocalAIService {
    var available: Bool
    var generatedText: String
    var generationError: Error?

    init(
        available: Bool,
        generatedText: String = "Local draft",
        generationError: Error? = nil
    ) {
        self.available = available
        self.generatedText = generatedText
        self.generationError = generationError
    }

    func isAvailable(for kind: CareBridgeAITaskKind) async -> Bool {
        available
    }

    func generateText(for task: LocalAITask) async throws -> String {
        if let generationError {
            throw generationError
        }
        return generatedText
    }
}

private final class AIBackendStub: MockDataService {
    var reply = "Backend draft"
    private(set) var receivedPrompts: [String] = []

    override func sendAIMessage(content: String) async throws -> AIMessage {
        receivedPrompts.append(content)
        return AIMessage(
            id: "backend-response",
            content: reply,
            isUser: false,
            timestamp: Date()
        )
    }
}

struct AIOrchestratorTests {
    @Test func lightweightTasksPreferLocalAppleModel() {
        let policy = AIOrchestrationPolicy()

        #expect(policy.preferredTarget(for: .rewriteCareNote) == .localApple)
        #expect(policy.preferredTarget(for: .summarizeVisibleContent) == .localApple)
        #expect(policy.preferredTarget(for: .classifyCareLog) == .localApple)
        #expect(policy.preferredTarget(for: .draftTodo) == .localApple)
    }

    @Test func highRiskAndLongContextTasksStayOnBackend() {
        let policy = AIOrchestrationPolicy()

        #expect(policy.preferredTarget(for: .generalChat) == .backend)
        #expect(policy.preferredTarget(for: .firstAid) == .backend)
        #expect(policy.preferredTarget(for: .careAnalysis) == .backend)
        #expect(policy.preferredTarget(for: .handoverReport) == .backend)
        #expect(policy.preferredTarget(for: .subsidyForm) == .backend)
    }

    @Test func localTasksFallBackToBackendWhenLocalModelUnavailable() {
        let policy = AIOrchestrationPolicy()

        #expect(
            policy.resolvedTarget(
                for: .rewriteCareNote,
                localModelAvailable: false
            ) == .backend
        )
        #expect(
            policy.resolvedTarget(
                for: .rewriteCareNote,
                localModelAvailable: true
            ) == .localApple
        )
    }

    @Test func localTextTasksAreDraftsRequiringUserConfirmation() {
        let task = LocalAITask(
            kind: .rewriteCareNote,
            input: "Grandma ate half of lunch and felt tired.",
            localeIdentifier: "en"
        )

        #expect(task.requiresUserConfirmation)
        #expect(task.systemInstructions.contains("draft"))
        #expect(task.prompt.contains("Grandma ate half of lunch and felt tired."))
    }

    @Test func availableLocalModelProducesLocalResponse() async throws {
        let backend = AIBackendStub()
        let local = LocalAIStub(
            available: true,
            generatedText: "Apple local draft"
        )
        let orchestrator = AIOrchestrator(
            dataService: backend,
            localAIService: local
        )

        let response = try await orchestrator.runTextTask(
            LocalAITask(
                kind: .rewriteCareNote,
                input: "Raw care note",
                localeIdentifier: "zh-TW"
            )
        )

        #expect(response.text == "Apple local draft")
        #expect(response.source == .localAppleFoundationModel)
        #expect(backend.receivedPrompts.isEmpty)
    }

    @Test func unavailableLocalModelUsesBackend() async throws {
        let backend = AIBackendStub()
        let orchestrator = AIOrchestrator(
            dataService: backend,
            localAIService: LocalAIStub(available: false)
        )

        let response = try await orchestrator.runTextTask(
            LocalAITask(
                kind: .summarizeVisibleContent,
                input: "Visible content",
                localeIdentifier: "zh-TW"
            )
        )

        #expect(response.text == "Backend draft")
        #expect(response.source == .backend)
        #expect(backend.receivedPrompts.count == 1)
    }

    @Test func localGenerationFailureFallsBackToBackend() async throws {
        let backend = AIBackendStub()
        let local = LocalAIStub(
            available: true,
            generationError: LocalAIStubError.generationFailed
        )
        let orchestrator = AIOrchestrator(
            dataService: backend,
            localAIService: local
        )

        let response = try await orchestrator.runTextTask(
            LocalAITask(
                kind: .rewriteCareNote,
                input: "Raw care note",
                localeIdentifier: "zh-TW"
            )
        )

        #expect(response.text == "Backend draft")
        #expect(response.source == .backend)
        #expect(backend.receivedPrompts.count == 1)
    }
}
