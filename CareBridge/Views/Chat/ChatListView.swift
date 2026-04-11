import SwiftUI

struct ChatListView: View {
    @Binding var showProfile: Bool
    @Binding var isInChatDetail: Bool
    let userRole: UserRole
    @State private var showPurchaseRequests = false
    @State private var showLeaveRequests = false
    @State private var showNotifications = false
    @State private var chatRooms = ChatRoom.samples
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 16) {
                    // Quick action buttons (採購核准 / 請假核准)
                    quickActionButtons

                    // Chat list
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("最近訊息")
                                .font(.system(size: 17, weight: .bold))
                            Spacer()
                            Button {
                                // New chat
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                            }
                        }

                        ForEach(chatRooms) { room in
                            NavigationLink(value: room) {
                                ChatRoomRow(room: room)
                            }
                            .buttonStyle(.plain)
                        }

                        if chatRooms.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("沒有更多訊息")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white))

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.brandTeal)
                            Text("CareBridge")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        Button { } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                }
            }
            .navigationDestination(for: ChatRoom.self) { room in
                ChatDetailView(room: room)
            }
            .navigationDestination(isPresented: $showPurchaseRequests) {
                MessageBoardView(userRole: userRole)
            }
            .navigationDestination(isPresented: $showLeaveRequests) {
                LeaveManagementView(userRole: userRole)
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .onChange(of: navPath.count) { _, newCount in
                isInChatDetail = newCount > 0
            }
        }
    }

    private var quickActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showPurchaseRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Text(userRole == .caregiver ? "採購需求" : "採購核准")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.brandTealLight))
                    if userRole == .family {
                        ZStack {
                            Circle().fill(.red).frame(width: 22, height: 22)
                            Text("1")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 6, y: -10)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                showLeaveRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Text(userRole == .caregiver ? "請假申請" : "請假核准")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.brandTealLight))
                    if userRole == .family {
                        ZStack {
                            Circle().fill(.red).frame(width: 22, height: 22)
                            Text("1")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .offset(x: 6, y: -10)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Chat Room Row
struct ChatRoomRow: View {
    let room: ChatRoom

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.brandTealLight)
                    .frame(width: 52, height: 52)
                Image(systemName: room.isGroup ? "person.3.fill" : "person.fill")
                    .foregroundStyle(Color.brandTeal)
                    .font(.system(size: room.isGroup ? 18 : 22))
                if room.unreadCount > 0 {
                    ZStack {
                        Circle().fill(.red).frame(width: 20, height: 20)
                        Text("\(room.unreadCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 18, y: -18)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(room.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(room.lastMessageTime.formatted(.relative(presentation: .named)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(room.lastMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Chat Detail View
struct ChatDetailView: View {
    let room: ChatRoom
    @State private var messages = ChatMessage.samples
    @State private var inputText = ""
    @State private var isRecording = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input bar
            inputBar
        }
        .background(Color.brandBackground)
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Button {
                // Attach
            } label: {
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
                    isRecording.toggle()
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
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newMsg = ChatMessage(
            id: UUID().uuidString,
            sender: "林小明", senderRole: .family,
            content: inputText, translatedContent: nil,
            timestamp: Date(), isMe: true
        )
        messages.append(newMsg)
        inputText = ""
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isMe { Spacer(minLength: 60) }

            if !message.isMe {
                Circle()
                    .fill(Color.brandTealLight)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandTeal)
                    }
            }

            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                if !message.isMe {
                    Text(message.sender)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(message.isMe ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(message.isMe
                                      ? Color.brandTeal
                                      : Color(.systemBackground))
                        )

                    if let translated = message.translatedContent {
                        Text(translated)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.systemGray6))
                            )
                    }
                }

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if message.isMe {
                Circle()
                    .fill(Color.brandTealLight)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandTeal)
                    }
            } else {
                Spacer(minLength: 60)
            }
        }
    }
}

#Preview {
    ChatListView(showProfile: .constant(false), isInChatDetail: .constant(false), userRole: .family)
}
