import SwiftUI

struct MessageBoardView: View {
    var userRole: UserRole = .family
    @Environment(\.dataService) private var service
    @State private var requests: [PurchaseRequest] = []
    @State private var selectedCategory = "全部"
    @State private var showAddRequest = false
    private let categories = ["全部", "食品", "日用品", "醫療用品", "其他"]

    var filteredRequests: [PurchaseRequest] {
        selectedCategory == "全部" ? requests : requests.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        FilterChip(title: cat, isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredRequests) { req in
                        PurchaseRequestCard(request: req,
                                            userRole: userRole,
                                            onApprove: { updateStatus(req, to: "approved") },
                                            onReject: { updateStatus(req, to: "rejected") })
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle(userRole == .caregiver ? "採購需求" : "採購核准")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if userRole == .caregiver {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRequest = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("新增需求")
                        }
                        .foregroundStyle(Color.brandTeal)
                        .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRequest) {
            AddPurchaseRequestView { newRequest in
                requests.insert(newRequest, at: 0)
            }
        }
        .task {
            requests = (try? await service.fetchPurchaseRequests()) ?? []
        }
    }

    private func updateStatus(_ request: PurchaseRequest, to status: String) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            withAnimation {
                requests[index] = PurchaseRequest(
                    id: request.id,
                    title: request.title,
                    category: request.category,
                    description: request.description,
                    estimatedCost: request.estimatedCost,
                    status: status,
                    createdAt: request.createdAt,
                    requester: request.requester,
                    notes: request.notes
                )
            }
        }
        Task { _ = try? await service.updatePurchaseRequestStatus(id: request.id, status: status) }
    }
}

// MARK: - Add Purchase Request View
struct AddPurchaseRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    let onAdd: (PurchaseRequest) -> Void

    @State private var itemName = ""
    @State private var itemQuantity = ""
    @State private var category = "食品"
    @State private var notes = ""
    @State private var isSubmitting = false

    private let categories = ["食品", "日用品", "醫療用品", "其他"]

    private var canSubmit: Bool { !itemName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("品項") {
                    TextField("物品名稱", text: $itemName)
                    TextField("數量（選填）", text: $itemQuantity)
                }
                Section("類別") {
                    Picker("類別", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("備註") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("新增採購需求")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("送出") {
                        Task {
                            isSubmitting = true
                            let item = PurchaseRequest.PurchaseItem(
                                name: itemName,
                                nameTranslated: nil,
                                quantity: itemQuantity.isEmpty ? nil : itemQuantity
                            )
                            let req = PurchaseRequest(
                                id: UUID().uuidString,
                                title: itemName,
                                category: category,
                                description: itemName,
                                estimatedCost: nil,
                                status: "pending",
                                createdAt: Date(),
                                requester: "",
                                notes: notes,
                                items: [item]
                            )
                            let created = (try? await service.createPurchaseRequest(req)) ?? req
                            onAdd(created)
                            dismiss()
                        }
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
    }
}

// MARK: - Purchase Request Card
struct PurchaseRequestCard: View {
    let request: PurchaseRequest
    let userRole: UserRole
    let onApprove: () -> Void
    let onReject: () -> Void
    @State private var replyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(request.category.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brandTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().stroke(Color.brandTeal, lineWidth: 1))
                Spacer()
                Text(request.statusDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(request.statusColor)
            }

            // Title
            Text(request.title)
                .font(.system(size: 18, weight: .bold))

            // Details grid
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("QUANTITY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("1 組")
                        .font(.system(size: 15, weight: .semibold))
                }
                if let cost = request.estimatedCost {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EST. COST")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("NT$\(Int(cost).formatted())")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }

            // Caregiver notes
            if !request.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAREGIVER NOTES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\"\(request.notes)\"")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            // Reply area (family only)
            if userRole == .family {
                VStack(alignment: .leading, spacing: 6) {
                    Text("意見與回饋給看護者 (選填)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("輸入您的意見...", text: $replyText, axis: .vertical)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                        .lineLimit(1...3)
                }
            }

            // Action buttons (only for pending, family can approve/reject)
            if request.status == "pending" && userRole == .family {
                HStack(spacing: 12) {
                    Button(action: onReject) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("拒絕")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("核准")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.brandTeal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}

#Preview {
    NavigationStack {
        MessageBoardView(userRole: .family)
    }
}
