import SwiftUI

struct AIAgentView: View {
    var isModal: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var dataService
    @State private var messages: [AIMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(messages) { msg in
                            AIMessageBubble(message: msg)
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
                    Button { dismiss() } label: {
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
                    Button { } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
        }
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
            Button { } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandTeal)
            }

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
        messages.append(AIMessage(id: UUID().uuidString, content: text, isUser: true, timestamp: Date()))
        inputText = ""
        isLoading = true
        Task { await streamAIResponse(prompt: text) }
    }

    /// SSE 串流接收 AI 回應，即時更新畫面；失敗時 fallback 到 mock
    private func streamAIResponse(prompt: String) async {
        let replyId = UUID().uuidString
        await MainActor.run {
            messages.append(AIMessage(id: replyId, content: "", isUser: false, timestamp: Date()))
        }

        do {
            var accumulated = ""
            for try await chunk in dataService.streamAIResponse(prompt: prompt) {
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
            }

            if accumulated.isEmpty {
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
        } catch {
            await MainActor.run {
                if let idx = messages.firstIndex(where: { $0.id == replyId }) {
                    messages[idx] = AIMessage(
                        id: replyId,
                        content: "AI response failed. Please try again.",
                        isUser: false,
                        timestamp: Date()
                    )
                }
            }
        }

        await MainActor.run { isLoading = false }
    }

}

// MARK: - AI Message Bubble
struct AIMessageBubble: View {
    let message: AIMessage

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
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
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

#Preview {
    NavigationStack {
        AIAgentView()
    }
}
