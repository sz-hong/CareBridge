import SwiftUI
import QuickLook

struct AIAgentView: View {
    var isModal: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var dataService
    @State private var messages: [AIMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var conversationID: String?
    @State private var responseTask: Task<Void, Never>?
    @State private var selectedTool: AIToolKind?
    @State private var documentPreviewURL: URL?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(messages) { msg in
                            AIMessageBubble(
                                message: msg,
                                onDocumentPreview: previewDocument
                            )
                                .id(msg.id)
                        }
                        if isLoading {
                            HStack {
                                typingIndicator
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 16)
                }
                .background(Color.brandBackground)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input bar
            aiInputBar
        }
        .background(Color.brandBackground)
        .navigationTitle("AI 智慧助理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        resetChatContext()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
        }
        .onDisappear {
            resetChatContext()
        }
        .sheet(item: $selectedTool) { tool in
            AIToolSheet(tool: tool) { document in
                appendGeneratedDocument(document)
            }
        }
        .quickLookPreview($documentPreviewURL)
    }

    // MARK: - Typing Indicator
    private var typingIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.4, green: 0.2, blue: 0.8))
            Text("AI 分析建議")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.4, green: 0.2, blue: 0.8))
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.93, green: 0.90, blue: 0.98)))
    }

    // MARK: - Input Bar
    private var aiInputBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(AIToolKind.allCases) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Label(tool.title, systemImage: tool.icon)
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandTeal)
            }
            .disabled(isLoading)

            TextField("輸入您的問題...", text: $inputText, axis: .vertical)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(.systemGray6)))
                .focused($isInputFocused)
                .lineLimit(1...4)

            Button {
                if inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // voice input
                } else {
                    sendMessage()
                }
            } label: {
                Image(systemName: inputText.isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandTeal)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard !isLoading else { return }
        messages.append(AIMessage(id: UUID().uuidString, content: text, isUser: true, timestamp: Date()))
        inputText = ""
        isLoading = true
        let activeConversationID = conversationID
        responseTask?.cancel()
        responseTask = Task {
            await streamAIResponse(
                prompt: text,
                conversationID: activeConversationID
            )
        }
    }

    /// SSE 串流接收 AI 回應，即時更新畫面；失敗時 fallback 到 mock
    private func streamAIResponse(prompt: String, conversationID: String?) async {
        let replyId = UUID().uuidString
        await MainActor.run {
            messages.append(AIMessage(id: replyId, content: "", isUser: false, timestamp: Date()))
        }

        do {
            var accumulated = ""
            for try await event in dataService.streamAIResponse(
                prompt: prompt,
                conversationID: conversationID
            ) {
                guard !Task.isCancelled else { break }
                switch event {
                case .chunk(let chunk):
                    accumulated += chunk
                    let updated = accumulated
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == replyId }) {
                            messages[idx] = AIMessage(
                                id: replyId,
                                content: updated,
                                isUser: false,
                                timestamp: Date()
                            )
                        }
                    }
                case .done(let conversationID):
                    await MainActor.run {
                        self.conversationID = conversationID
                    }
                case .ignore:
                    continue
                }
            }

            if accumulated.isEmpty && !Task.isCancelled {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == replyId }) {
                        messages[idx] = AIMessage(
                            id: replyId,
                            content: "AI response completed without content.",
                            isUser: false,
                            timestamp: Date()
                        )
                    }
                }
            }
        } catch is CancellationError {
            // Closing the chat cancels the active stream.
        } catch {
            let wasCancelled = Task.isCancelled
            await MainActor.run {
                if !wasCancelled,
                   let idx = messages.firstIndex(where: { $0.id == replyId }) {
                    messages[idx] = AIMessage(
                        id: replyId,
                        content: "AI response failed. Please try again.",
                        isUser: false,
                        timestamp: Date()
                    )
                }
            }
        }

        await MainActor.run {
            isLoading = false
            responseTask = nil
        }
    }

    @MainActor
    private func appendGeneratedDocument(_ document: AIGeneratedDocument) {
        messages.append(
            AIMessage(
                id: UUID().uuidString,
                content: "\(document.title) 已產生，點擊文件預覽。",
                isUser: false,
                timestamp: Date(),
                document: document
            )
        )
    }

    @MainActor
    private func previewDocument(_ document: AIGeneratedDocument) {
        do {
            documentPreviewURL = try document.writeTemporaryFile()
        } catch {
            messages.append(
                AIMessage(
                    id: UUID().uuidString,
                    content: "文件預覽失敗：\(error.localizedDescription)",
                    isUser: false,
                    timestamp: Date()
                )
            )
        }
    }

    private func resetChatContext() {
        responseTask?.cancel()
        responseTask = nil
        messages = []
        conversationID = nil
        inputText = ""
        isLoading = false
        documentPreviewURL = nil
    }

}

private enum AIToolKind: String, CaseIterable, Identifiable {
    case careAnalysis
    case handoverReport
    case subsidyForm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .careAnalysis: return "照護報告"
        case .handoverReport: return "交接報告"
        case .subsidyForm: return "補助表單"
        }
    }

    var icon: String {
        switch self {
        case .careAnalysis: return "chart.line.uptrend.xyaxis"
        case .handoverReport: return "doc.text"
        case .subsidyForm: return "square.and.pencil"
        }
    }

    var actionTitle: String {
        switch self {
        case .careAnalysis: return "產生照護報告"
        case .handoverReport: return "產生交接報告"
        case .subsidyForm: return "產生表單"
        }
    }
}

private struct AIToolSheet: View {
    let tool: AIToolKind
    let onDocumentGenerated: (AIGeneratedDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var dataService
    @State private var days = 7
    @State private var reportDate = Date()
    @State private var subsidyFormType = "long_term_care"
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let requestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    inputControls
                }

                Section {
                    Button {
                        Task { await runTool() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                            }
                            Text(tool.actionTitle)
                        }
                    }
                    .disabled(isLoading)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var inputControls: some View {
        switch tool {
        case .careAnalysis:
            Stepper(value: $days, in: 1...30) {
                Text("分析最近 \(days) 天")
            }
        case .handoverReport:
            DatePicker(
                "交接日期",
                selection: $reportDate,
                displayedComponents: .date
            )
        case .subsidyForm:
            Picker("表單類型", selection: $subsidyFormType) {
                Text("長照補助").tag("long_term_care")
                Text("身障補助").tag("disability")
                Text("喘息服務").tag("respite_care")
            }
        }
    }

    @MainActor
    private func runTool() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let document: AIGeneratedDocument
            switch tool {
            case .careAnalysis:
                let response = try await dataService.fetchCareAnalysis(days: days)
                document = AIGeneratedDocument.careAnalysis(response)
            case .handoverReport:
                let date = Self.requestDateFormatter.string(from: reportDate)
                let response = try await dataService.generateHandoverReport(date: date)
                document = AIGeneratedDocument.handoverReport(response)
            case .subsidyForm:
                let response = try await dataService.generateSubsidyForm(
                    formType: subsidyFormType
                )
                document = AIGeneratedDocument.subsidyForm(response)
            }
            onDocumentGenerated(document)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - AI Message Bubble
struct AIMessageBubble: View {
    let message: AIMessage
    let onDocumentPreview: (AIGeneratedDocument) -> Void

    var body: some View {
        HStack(alignment: .top) {
            if message.isUser {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.brandTeal)
                    )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.4, green: 0.2, blue: 0.8))
                        Text("AI 分析建議")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.4, green: 0.2, blue: 0.8))
                    }
                    if let document = message.document {
                        AIGeneratedDocumentBubbleContent(
                            message: message,
                            document: document,
                            onPreview: {
                                onDocumentPreview(document)
                            }
                        )
                    } else {
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.93, green: 0.90, blue: 0.98))
                )
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct AIGeneratedDocumentBubbleContent: View {
    let message: AIMessage
    let document: AIGeneratedDocument
    let onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.brandTeal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(message.content)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(document.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Image(systemName: "doc.viewfinder")
                    Text("預覽文件")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch document.kind {
        case .careAnalysis:
            return "chart.line.uptrend.xyaxis"
        case .handoverReport:
            return "doc.text"
        case .subsidyForm:
            return "square.and.pencil"
        }
    }
}

#Preview {
    NavigationStack {
        AIAgentView()
    }
}
