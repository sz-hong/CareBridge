import SwiftUI
import QuickLook
import UniformTypeIdentifiers

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

    private var scrollTrigger: String {
        let lastMessage = messages.last
        return [
            String(messages.count),
            String(lastMessage?.content.count ?? 0),
            String(isLoading),
        ].joined(separator: "-")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if messages.isEmpty {
                            aiWelcome
                        }

                        ForEach(messages) { msg in
                            AIMessageBubble(
                                message: msg,
                                isThinking: isLoading
                                    && msg.id == messages.last?.id
                                    && !msg.isUser
                                    && msg.content.isEmpty,
                                onDocumentPreview: previewDocument
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .background(Color.brandBackground)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: scrollTrigger) {
                    if let last = messages.last {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            aiInputBar
        }
        .background(Color.brandBackground)
        .navigationTitle("CareBridge AI")
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
                Menu {
                    Section("AI 工具") {
                        ForEach(AIToolKind.allCases) { tool in
                            Button {
                                selectedTool = tool
                            } label: {
                                Label(tool.title, systemImage: tool.icon)
                            }
                        }
                    }

                    if !messages.isEmpty {
                        Button {
                            resetChatContext()
                        } label: {
                            Label("開始新對話", systemImage: "square.and.pencil")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                }
                .disabled(isLoading)
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

    private var aiWelcome: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.brandTeal.opacity(0.18),
                                Color.purple.opacity(0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 74, height: 74)

                Image(systemName: "sparkles")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.brandTeal, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("有什麼我能幫忙的？")
                    .font(.system(size: 25, weight: .bold))

                Text("可以詢問照護、健康紀錄，或請我協助整理重點。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                suggestionButton(
                    title: "整理今天的照護重點",
                    icon: "text.document"
                )
                suggestionButton(
                    title: "最近有哪些健康狀況需要注意？",
                    icon: "heart.text.clipboard"
                )
            }
            .frame(maxWidth: 420)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AIToolKind.allCases) { tool in
                        Button {
                            selectedTool = tool
                        } label: {
                            Label(tool.title, systemImage: tool.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemBackground))
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(Color(.systemGray5), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 56)
    }

    // MARK: - Input Bar
    private var aiInputBar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("詢問照護相關問題", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .frame(minHeight: 32, alignment: .center)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(canSend ? Color.brandTeal : Color(.systemGray4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("送出訊息")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    isLoading
                        ? Color.brandTeal.opacity(0.18)
                        : Color(.systemGray5),
                    lineWidth: 1
                )
        }
        .aiThinkingBeam(active: isLoading, cornerRadius: 24)
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
    }

    private func suggestionButton(title: String, icon: String) -> some View {
        Button {
            inputText = title
            sendMessage()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isLoading else { return }

        let replyID = UUID().uuidString
        messages.append(
            AIMessage(
                id: UUID().uuidString,
                content: text,
                isUser: true,
                timestamp: Date()
            )
        )
        messages.append(
            AIMessage(
                id: replyID,
                content: "",
                isUser: false,
                timestamp: Date()
            )
        )
        inputText = ""
        isLoading = true
        let activeConversationID = conversationID
        responseTask?.cancel()
        responseTask = Task {
            await streamAIResponse(
                prompt: text,
                conversationID: activeConversationID,
                replyID: replyID
            )
        }
    }

    /// SSE 串流接收 AI 回應，即時更新畫面；失敗時 fallback 到 mock
    private func streamAIResponse(
        prompt: String,
        conversationID: String?,
        replyID: String
    ) async {
        do {
            var accumulated = ""
            var streamFailed = false
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
                        if let idx = messages.firstIndex(where: { $0.id == replyID }) {
                            messages[idx] = AIMessage(
                                id: replyID,
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
                case .error(let message):
                    streamFailed = true
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == replyID }) {
                            messages[idx] = AIMessage(
                                id: replyID,
                                content: message,
                                isUser: false,
                                timestamp: Date()
                            )
                        }
                    }
                case .ignore:
                    continue
                }
            }

            if accumulated.isEmpty && !streamFailed && !Task.isCancelled {
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == replyID }) {
                        messages[idx] = AIMessage(
                            id: replyID,
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
                   let idx = messages.firstIndex(where: { $0.id == replyID }) {
                    messages[idx] = AIMessage(
                        id: replyID,
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
    @State private var showTemplateImporter = false
    @State private var selectedTemplateFileName: String?
    @State private var selectedTemplateFileData: Data?
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
            .fileImporter(
                isPresented: $showTemplateImporter,
                allowedContentTypes: [.json, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleTemplateImport(result)
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
            VStack(alignment: .leading, spacing: 12) {
                Picker("表單類型", selection: $subsidyFormType) {
                    Text("長照補助").tag("long_term_care")
                    Text("身障補助").tag("disability")
                    Text("喘息服務").tag("respite_care")
                    Text("上傳表單").tag("uploaded_template")
                }

                Button {
                    showTemplateImporter = true
                } label: {
                    Label(
                        selectedTemplateFileName ?? "選擇表單格式檔",
                        systemImage: "doc.badge.plus"
                    )
                }
                .disabled(isLoading)

                if subsidyFormType == "uploaded_template" {
                    Text("請上傳純文字或 JSON 表單格式；系統會依欄位產生預填內容。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func runTool() async {
        guard !isLoading else { return }
        if tool == .subsidyForm,
           subsidyFormType == "uploaded_template",
           selectedTemplateFileData == nil {
            errorMessage = "請先選擇表單格式檔。"
            return
        }
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
                let usesUploadedTemplate = subsidyFormType == "uploaded_template"
                let response = try await dataService.generateSubsidyForm(
                    formType: subsidyFormType,
                    templateFileName: usesUploadedTemplate ? selectedTemplateFileName : nil,
                    templateFileData: usesUploadedTemplate ? selectedTemplateFileData : nil
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

    private func handleTemplateImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            selectedTemplateFileData = try Data(contentsOf: url)
            selectedTemplateFileName = url.lastPathComponent
            subsidyFormType = "uploaded_template"
            errorMessage = nil
        } catch {
            selectedTemplateFileData = nil
            selectedTemplateFileName = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - AI Message Bubble
struct AIMessageBubble: View {
    let message: AIMessage
    let isThinking: Bool
    let onDocumentPreview: (AIGeneratedDocument) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer(minLength: 52)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.brandTeal)
                        )

                    messageTime
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.brandTeal.opacity(0.18),
                                    Color.purple.opacity(0.16),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if isThinking {
                        HStack(spacing: 8) {
                            Text("正在思考")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)

                            ThinkingDots()
                        }
                        .frame(minHeight: 24)
                    } else {
                        HStack(spacing: 6) {
                            Text("CareBridge AI")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }

                    if !isThinking, let document = message.document {
                        AIGeneratedDocumentBubbleContent(
                            message: message,
                            document: document,
                            onPreview: {
                                onDocumentPreview(document)
                            }
                        )
                    } else if !isThinking {
                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    if !isThinking {
                        messageTime
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemBackground))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isThinking
                                ? Color.brandTeal.opacity(0.16)
                                : Color(.systemGray5),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)

                Spacer(minLength: 28)
            }
        }
        .padding(.horizontal, 16)
    }

    private var messageTime: some View {
        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }
}

private struct ThinkingDots: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.brandTeal)
                    .frame(width: 5, height: 5)
                    .phaseAnimator([0.55, 1.0, 0.55]) { content, opacity in
                        content
                            .opacity(opacity)
                            .scaleEffect(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.55)
                            .delay(Double(index) * 0.12)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AIThinkingBeamModifier: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat

    @State private var phase: Double = 0
    @State private var breath = 0.55

    private var beamGradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.36),
                .init(color: Color.brandTeal.opacity(0.95), location: 0.41),
                .init(
                    color: Color(red: 0.20, green: 0.70, blue: 0.76),
                    location: 0.47
                ),
                .init(
                    color: Color(red: 0.39, green: 0.48, blue: 0.84),
                    location: 0.53
                ),
                .init(
                    color: Color(red: 0.65, green: 0.45, blue: 0.82),
                    location: 0.59
                ),
                .init(color: .clear, location: 0.67),
                .init(color: .clear, location: 1),
            ],
            center: .center,
            startAngle: .degrees(phase),
            endAngle: .degrees(phase + 360)
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    let shape = RoundedRectangle(cornerRadius: cornerRadius)

                    ZStack {
                        beamGradient
                            .mask {
                                shape.strokeBorder(lineWidth: 4.5)
                            }
                            .blur(radius: 4)
                            .opacity(breath * 0.72)

                        beamGradient
                            .mask {
                                shape.strokeBorder(lineWidth: 1.5)
                            }
                            .opacity(min(breath + 0.18, 1))
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        phase = 0
                        breath = 0.55
                        withAnimation(
                            .linear(duration: 2.6)
                                .repeatForever(autoreverses: false)
                        ) {
                            phase = 360
                        }
                        withAnimation(
                            .easeInOut(duration: 1.3)
                                .repeatForever(autoreverses: true)
                        ) {
                            breath = 1
                        }
                    }
                }
            }
    }
}

private extension View {
    func aiThinkingBeam(
        active: Bool,
        cornerRadius: CGFloat
    ) -> some View {
        modifier(
            AIThinkingBeamModifier(
                active: active,
                cornerRadius: cornerRadius
            )
        )
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
