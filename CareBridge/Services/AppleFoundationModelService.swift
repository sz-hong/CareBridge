import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
final class AppleFoundationModelService: LocalAIService {
    func isAvailable(for kind: CareBridgeAITaskKind) async -> Bool {
        guard kind.prefersLocalAppleModel else {
            return false
        }

        let model = SystemLanguageModel()
        #if DEBUG
        print(
            "[FoundationModels] availability: "
            + String(describing: model.availability)
        )
        #endif
        if case .available = model.availability {
            return true
        }
        return false
    }

    func generateText(for task: LocalAITask) async throws -> String {
        guard await isAvailable(for: task.kind) else {
            throw LocalAIServiceError.unavailable(
                "Apple Foundation Models are not available on this device."
            )
        }

        let session = LanguageModelSession(
            model: SystemLanguageModel(),
            instructions: task.systemInstructions
        )
        let response = try await session.respond(to: task.prompt)
        let text = response.content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !text.isEmpty else {
            throw LocalAIServiceError.emptyResponse
        }
        return text
    }
}
#else
final class AppleFoundationModelService: LocalAIService {
    func isAvailable(for kind: CareBridgeAITaskKind) async -> Bool {
        false
    }

    func generateText(for task: LocalAITask) async throws -> String {
        throw LocalAIServiceError.unavailable(
            "Apple Foundation Models are not available in this build."
        )
    }
}
#endif
