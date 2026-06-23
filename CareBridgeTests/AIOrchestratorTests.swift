import Foundation
import Testing
@testable import CareBridge

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
}
