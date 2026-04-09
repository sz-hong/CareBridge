import SwiftUI

struct MessageBoardView: View {
    @State private var requests = PurchaseRequest.samples
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
                                            onApprove: { updateStatus(req, to: "已核准") },
                                            onReject: { updateStatus(req, to: "已駁回") })
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("採購核准")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddRequest = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.brandTeal)
                        .font(.system(size: 22))
                }
            }
        }
        .sheet(isPresented: $showAddRequest) {
            Text("新增採購需求")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.brandBackground)
        }
    }

    private func updateStatus(_ request: PurchaseRequest, to status: String) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            withAnimation {
                requests[index] = PurchaseRequest(
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
    }
}

// MARK: - Purchase Request Card
struct PurchaseRequestCard: View {
    let request: PurchaseRequest
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
                Text(request.status)
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

            // Reply area
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

            // Action buttons (only for pending)
            if request.status == "待確認" {
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
        MessageBoardView()
    }
}
