import SwiftUI

/// 採購需求詳情頁 — 從聊天室卡片點入
/// 看護：查看自己的需求狀態
/// 家屬：核准或拒絕
struct PurchaseRequestDetailView: View {
    let requestId: String
    let userRole: UserRole
    @Environment(\.dataService) private var service
    @Environment(LocaleStore.self) private var localeStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var request: PurchaseRequest?
    @State private var isLoading = true
    @State private var replyText = ""

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let req = request {
                ScrollView {
                    VStack(spacing: 16) {
                        requestCard(req)
                        if req.status == "pending" && userRole == .family {
                            approvalSection(req)
                        }
                    }
                    .frame(maxWidth: usesWideLayout ? 760 : .infinity)
                    .padding(usesWideLayout ? 24 : 16)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("找不到此採購需求", systemImage: "cart")
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("採購需求")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRequest() }
    }

    // MARK: - Card
    private func requestCard(_ req: PurchaseRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(req.category.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brandTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().stroke(Color.brandTeal, lineWidth: 1))
                Spacer()
                Text(req.statusDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(req.statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(req.statusColor.opacity(0.12)))
            }

            Text(req.displayTitle(language: localeStore.code))
                .font(.system(size: 20, weight: .bold))

            // Items
            if !req.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("品項")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(req.items, id: \.name) { item in
                        HStack {
                            Text(item.displayName(language: localeStore.code))
                                .font(.system(size: 15))
                            Spacer()
                            if let qty = item.quantity {
                                Text(qty)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let cost = req.estimatedCost {
                HStack {
                    Text("預估費用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("NT$\(Int(cost).formatted())")
                        .font(.system(size: 16, weight: .bold))
                }
            }

            if !req.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("備註")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(req.displayNotes(language: localeStore.code))
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            if let reply = req.displayReply(language: localeStore.code), !reply.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("家屬回覆")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(reply)
                        .font(.system(size: 14))
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("申請人：\(req.requester)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(req.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Approval
    private func approvalSection(_ req: PurchaseRequest) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("意見與回饋（選填）")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("輸入您的意見...", text: $replyText, axis: .vertical)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                    .lineLimit(1...3)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await updateStatus(req, to: "rejected") }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("拒絕")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 1.5))
                }

                Button {
                    Task { await updateStatus(req, to: "approved") }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("核准")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.brandTeal))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Actions
    private func loadRequest() async {
        isLoading = true
        // Fetch all and find by ID (until single-item endpoint exists)
        let all = (try? await service.fetchPurchaseRequests()) ?? []
        request = all.first { $0.id == requestId }
        isLoading = false
    }

    private func updateStatus(_ req: PurchaseRequest, to status: String) async {
        if let updated = try? await service.updatePurchaseRequestStatus(id: req.id, status: status) {
            withAnimation { request = updated }
        } else {
            // Optimistic local update
            var copy = req
            copy.status = status
            withAnimation { request = copy }
        }
    }
}
