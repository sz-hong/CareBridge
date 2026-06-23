import Foundation
import SwiftUI

protocol AIOrchestrating {
    func runTextTask(_ task: LocalAITask) async throws -> AITextTaskResponse
}

final class AIOrchestrator: AIOrchestrating {
    private let dataService: DataService
    private let localAIService: LocalAIService
    private let policy: AIOrchestrationPolicy

    init(
        dataService: DataService,
        localAIService: LocalAIService,
        policy: AIOrchestrationPolicy = AIOrchestrationPolicy()
    ) {
        self.dataService = dataService
        self.localAIService = localAIService
        self.policy = policy
    }

    func runTextTask(_ task: LocalAITask) async throws -> AITextTaskResponse {
        let localAvailable = await localAIService.isAvailable(for: task.kind)
        let target = policy.resolvedTarget(
            for: task.kind,
            localModelAvailable: localAvailable
        )

        switch target {
        case .localApple:
            let text = try await localAIService.generateText(for: task)
            return AITextTaskResponse(
                text: text,
                source: .localAppleFoundationModel,
                requiresUserConfirmation: task.requiresUserConfirmation
            )
        case .backend:
            let message = try await dataService.sendAIMessage(
                content: task.backendPrompt
            )
            return AITextTaskResponse(
                text: message.content,
                source: .backend,
                requiresUserConfirmation: task.requiresUserConfirmation
            )
        }
    }
}

private struct AIOrchestratorKey: EnvironmentKey {
    static let defaultValue: AIOrchestrating = AIOrchestrator(
        dataService: MockDataService(),
        localAIService: AppleFoundationModelService()
    )
}

extension EnvironmentValues {
    var aiOrchestrator: AIOrchestrating {
        get { self[AIOrchestratorKey.self] }
        set { self[AIOrchestratorKey.self] = newValue }
    }
}
