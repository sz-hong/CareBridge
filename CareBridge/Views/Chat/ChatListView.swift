import SwiftUI

struct ChatListView: View {
    @Binding var showProfile: Bool
    @Binding var isInChatDetail: Bool
    let userRole: UserRole
    @Environment(\.dataService) private var service
    @State private var showNotifications = false
    @State private var chatRooms: [ChatRoom] = []
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 16) {
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
                ChatDetailView(room: room, userRole: userRole)
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .onChange(of: navPath.count) { _, newCount in
                isInChatDetail = newCount > 0
            }
            .task {
                chatRooms = (try? await service.fetchChatRooms()) ?? []
            }
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

// MARK: - WebSocket Manager

@Observable
class ChatWebSocket {
    private var task: URLSessionWebSocketTask?
    private var roomId: String?
    private var isClosing = false      // disconnect() 設 true 防止 retry 干擾
    private var retryCount = 0
    var isConnected = false
    var onReceive: ((ChatMessage) -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func connect(roomId: String) {
        self.roomId = roomId
        self.isClosing = false
        openSocket()
    }

    private func openSocket() {
        guard let roomId else { return }
        var urlString = "\(AppConfig.wsBaseURL)/chat/\(roomId)/"
        if let token = KeychainService.accessToken {
            urlString += "?token=\(token)"
        }
        guard let url = URL(string: urlString) else { return }
        task = URLSession.shared.webSocketTask(with: url)
        task?.resume()
        DispatchQueue.main.async { self.isConnected = true }
        receiveLoop()
    }

    func send(content: String, sender: String, senderRole: UserRole) {
        guard isConnected else { return }
        let payload: [String: String] = ["content": content, "sender": sender, "senderRole": senderRole.rawValue]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(json)) { _ in }
    }

    func sendRequest(messageType: String, referenceId: String, content: String, sender: String, senderRole: UserRole) {
        guard isConnected else { return }
        let payload: [String: String] = [
            "content": content, "sender": sender, "senderRole": senderRole.rawValue,
            "message_type": messageType, "reference_id": referenceId
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(json)) { _ in }
    }

    func disconnect() {
        isClosing = true
        roomId = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.retryCount = 0
                if let data = text.data(using: .utf8),
                   let msg = try? self.decoder.decode(ChatMessage.self, from: data) {
                    DispatchQueue.main.async { self.onReceive?(msg) }
                }
                self.receiveLoop()
            case .success(.data):
                self.receiveLoop()
            case .failure:
                DispatchQueue.main.async { self.isConnected = false }
                self.scheduleReconnect()
            @unknown default:
                break
            }
        }
    }

    /// Exponential backoff reconnect (1s, 2s, 4s, ... capped at 16s) so a
    /// transient network glitch or backend restart doesn't permanently kill
    /// the chat. Caller can still drop everything via `disconnect()`.
    private func scheduleReconnect() {
        guard !isClosing, roomId != nil else { return }
        let delay = min(pow(2.0, Double(retryCount)), 16.0)
        retryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isClosing else { return }
            self.openSocket()
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    let room: ChatRoom
    let userRole: UserRole
    @Environment(\.dataService) private var service
    @Environment(UserStore.self) private var userStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isRecording = false
    @FocusState private var isInputFocused: Bool
    @State private var socket = ChatWebSocket()
    @State private var showPlusMenu = false
    @State private var showAddPurchase = false
    @State private var showAddLeave = false
    // Family-side approval shortcuts (jump to board / leave management)
    @State private var showBoardApproval = false
    @State private var showLeaveApproval = false
    // Navigation to detail views
    @State private var selectedPurchaseId: String?
    @State private var selectedLeaveId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            if msg.messageType == "purchase_request" || msg.messageType == "leave_request" {
                                RequestCardBubble(message: msg, userRole: userRole) {
                                    if msg.messageType == "purchase_request" {
                                        selectedPurchaseId = msg.referenceId
                                    } else {
                                        selectedLeaveId = msg.referenceId
                                    }
                                }
                                .id(msg.id)
                            } else {
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // 連線狀態
            if socket.isConnected {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("即時連線中").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
            }

            // Input bar
            inputBar
        }
        .background(Color.brandBackground)
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 設 onReceive 一定要在 connect 之前，避免 server 在 connect
            // 完成的瞬間就推訊息但 callback 還是 nil。
            socket.onReceive = { msg in handleIncoming(msg) }
            socket.connect(roomId: room.id)
            messages = (try? await service.fetchMessages(roomId: room.id)) ?? []
        }
        .onChange(of: scenePhase) { _, newPhase in
            // App 從背景回前景時重新拉一次歷史並確保 WS 還活著。
            // WebSocket 在背景一段時間後會被 iOS 砍，這裡兜底重連。
            guard newPhase == .active else { return }
            if !socket.isConnected {
                socket.connect(roomId: room.id)
            }
            Task {
                if let fresh = try? await service.fetchMessages(roomId: room.id) {
                    mergeFetched(fresh)
                }
            }
        }
        .onDisappear { socket.disconnect() }
        .navigationDestination(item: $selectedPurchaseId) { purchaseId in
            PurchaseRequestDetailView(requestId: purchaseId, userRole: userRole)
        }
        .navigationDestination(item: $selectedLeaveId) { leaveId in
            LeaveRequestDetailView(requestId: leaveId, userRole: userRole)
        }
        .navigationDestination(isPresented: $showBoardApproval) {
            MessageBoardView(userRole: userRole)
        }
        .navigationDestination(isPresented: $showLeaveApproval) {
            LeaveManagementView(userRole: userRole)
        }
        .sheet(isPresented: $showAddPurchase) {
            AddPurchaseRequestView { newRequest in
                sendRequestCard(type: "purchase_request", id: newRequest.id,
                                content: "📦 採購需求：\(newRequest.title)")
            }
        }
        .sheet(isPresented: $showAddLeave) {
            AddLeaveRequestView { newRequest in
                let fmt = DateFormatter(); fmt.dateFormat = "M/d"
                sendRequestCard(type: "leave_request", id: newRequest.id,
                                content: "📋 請假申請：\(newRequest.typeDisplayName) \(fmt.string(from: newRequest.startDate))–\(fmt.string(from: newRequest.endDate))")
            }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 12) {
            // "+" button — caregivers initiate requests, family members
            // jump to the corresponding approval screen.
            Menu {
                if userRole == .caregiver {
                    Button { showAddPurchase = true } label: {
                        Label("採購需求", systemImage: "cart.fill")
                    }
                    Button { showAddLeave = true } label: {
                        Label("請假申請", systemImage: "calendar.badge.clock")
                    }
                } else {
                    Button { showBoardApproval = true } label: {
                        Label("採購核准", systemImage: "cart.fill")
                    }
                    Button { showLeaveApproval = true } label: {
                        Label("請假核准", systemImage: "calendar.badge.clock")
                    }
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandTeal)
            }

            TextField("輸入訊息...", text: $inputText, axis: .vertical)
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

    // MARK: - Send Helpers
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let me = userStore.currentUser
        let newMsg = ChatMessage(
            id: UUID().uuidString,
            sender: me?.name ?? "",
            senderId: me?.id,
            senderRole: me?.role ?? .family,
            content: text, translations: nil,
            timestamp: Date(), isMe: true
        )
        messages.append(newMsg)
        inputText = ""

        // REST guarantees the message lands in the DB even if the WebSocket
        // happens to be reconnecting. The backend's chat ViewSet broadcasts
        // through the channel layer, so the WS echo arrives shortly after
        // and `handleIncoming()` reconciles the optimistic copy. Failure
        // path falls back to a fetch so we never end up with a "ghost"
        // message that only lives in this view's state.
        Task {
            if (try? await service.sendMessage(roomId: room.id, content: text)) == nil {
                messages = (try? await service.fetchMessages(roomId: room.id)) ?? messages
            }
        }
    }

    private func sendRequestCard(type: String, id: String, content: String) {
        let me = userStore.currentUser
        let newMsg = ChatMessage(
            id: UUID().uuidString,
            sender: me?.name ?? "",
            senderId: me?.id,
            senderRole: me?.role ?? .family,
            content: content, translations: nil,
            timestamp: Date(), isMe: true,
            messageType: type, referenceId: id
        )
        messages.append(newMsg)
        // REST path (saves to DB + broadcasts via channel layer to other
        // clients). The optimistic message above is reconciled with the WS
        // echo by handleIncoming(); on failure we fall back to a fetch so
        // the card still ends up persisted in the chat history.
        Task {
            if (try? await service.sendRequestMessage(
                roomId: room.id, messageType: type,
                referenceId: id, content: content
            )) == nil {
                messages = (try? await service.fetchMessages(roomId: room.id)) ?? messages
            }
        }
    }

    /// 把 server 拉回的訊息合併到本地，保留尚未 echo 回來的 optimistic 訊息。
    private func mergeFetched(_ fresh: [ChatMessage]) {
        let serverIds = Set(fresh.map { $0.id })
        // 保留本地有但 server 還沒回的（自己剛送、還沒收到 echo）
        let stillPending = messages.filter { msg in
            msg.isMe && !serverIds.contains(msg.id)
        }
        messages = fresh + stillPending
    }

    /// Merge an incoming WS message
    private func handleIncoming(_ msg: ChatMessage) {
        var incoming = msg
        if let myId = userStore.currentUser?.id, incoming.senderId == myId {
            incoming.isMe = true
            if let idx = messages.firstIndex(where: {
                $0.isMe && $0.translations == nil && $0.content == incoming.content
            }) {
                messages[idx] = incoming
                return
            }
        }
        guard !messages.contains(where: { $0.id == incoming.id }) else { return }
        messages.append(incoming)
    }
}

// MARK: - Request Card Bubble (interactive message in chat)
struct RequestCardBubble: View {
    let message: ChatMessage
    let userRole: UserRole
    let onTap: () -> Void

    private var isPurchase: Bool { message.messageType == "purchase_request" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isMe { Spacer(minLength: 40) }

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

                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: isPurchase ? "cart.fill" : "calendar.badge.clock")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(isPurchase ? Color.orange : Color.blue))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isPurchase ? "採購需求" : "請假申請")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(message.content.replacing(/^[📦📋]\s*/, with: ""))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        HStack {
                            Text("點擊查看詳情")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.brandTeal)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: 260, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGray4), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

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
                Spacer(minLength: 40)
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    @Environment(UserStore.self) private var userStore

    private var translatedText: String? {
        message.translation(for: userStore.currentUser?.language)
    }

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

                    if let translated = translatedText {
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
