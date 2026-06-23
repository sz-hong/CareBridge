import Foundation

enum CareBridgeAITaskKind: Equatable {
    case rewriteCareNote
    case summarizeVisibleContent
    case classifyCareLog
    case draftTodo
    case generalChat
    case firstAid
    case careAnalysis
    case handoverReport
    case subsidyForm

    var prefersLocalAppleModel: Bool {
        switch self {
        case .rewriteCareNote,
             .summarizeVisibleContent,
             .classifyCareLog,
             .draftTodo:
            return true
        case .generalChat,
             .firstAid,
             .careAnalysis,
             .handoverReport,
             .subsidyForm:
            return false
        }
    }

    var requiresUserConfirmation: Bool {
        switch self {
        case .rewriteCareNote,
             .summarizeVisibleContent,
             .classifyCareLog,
             .draftTodo:
            return true
        case .generalChat,
             .firstAid,
             .careAnalysis,
             .handoverReport,
             .subsidyForm:
            return false
        }
    }
}

enum AIExecutionTarget: Equatable {
    case localApple
    case backend
}

enum AIResponseSource: Equatable {
    case localAppleFoundationModel
    case backend
}

struct AIOrchestrationPolicy {
    func preferredTarget(for kind: CareBridgeAITaskKind) -> AIExecutionTarget {
        kind.prefersLocalAppleModel ? .localApple : .backend
    }

    func resolvedTarget(
        for kind: CareBridgeAITaskKind,
        localModelAvailable: Bool
    ) -> AIExecutionTarget {
        guard preferredTarget(for: kind) == .localApple else {
            return .backend
        }
        return localModelAvailable ? .localApple : .backend
    }
}

struct LocalAITask: Equatable {
    var kind: CareBridgeAITaskKind
    var input: String
    var localeIdentifier: String?

    var requiresUserConfirmation: Bool {
        kind.requiresUserConfirmation
    }

    var systemInstructions: String {
        switch kind {
        case .rewriteCareNote:
            return """
            You help caregivers write concise care coordination drafts.
            Rewrite only the provided text. Keep facts unchanged.
            Return a draft that a human must review before saving.
            """
        case .summarizeVisibleContent:
            return """
            You summarize only the visible text provided by the app.
            Do not add medical, legal, or financial advice.
            Return a short draft summary that a human must review.
            """
        case .classifyCareLog:
            return """
            You classify a care log draft into one label.
            Allowed labels: vital, medication, meal, activity, note.
            Return only the label and a short reason. This is a draft.
            """
        case .draftTodo:
            return """
            You convert a caregiver request into a todo draft.
            Include a short title and optional notes. Do not schedule anything.
            Return a draft that a human must review before saving.
            """
        case .generalChat,
             .firstAid,
             .careAnalysis,
             .handoverReport,
             .subsidyForm:
            return """
            Use the backend assistant for this task.
            """
        }
    }

    var prompt: String {
        let languageLine = localeIdentifier.map { "Preferred language: \($0)\n" } ?? ""
        return """
        \(languageLine)Task: \(kind)
        Input:
        \(input)
        """
    }

    var backendPrompt: String {
        """
        \(systemInstructions)

        \(prompt)
        """
    }
}

struct AITextTaskResponse: Equatable {
    var text: String
    var source: AIResponseSource
    var requiresUserConfirmation: Bool
}

protocol LocalAIService {
    func isAvailable(for kind: CareBridgeAITaskKind) async -> Bool
    func generateText(for task: LocalAITask) async throws -> String
}

enum LocalAIServiceError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason
        case .emptyResponse:
            return "The local model returned an empty response."
        }
    }
}
