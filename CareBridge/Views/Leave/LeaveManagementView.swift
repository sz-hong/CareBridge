import SwiftUI

struct LeaveManagementView: View {
    var userRole: UserRole = .family
    @Environment(\.dataService) private var service
    @State private var requests: [LeaveRequest] = []
    @State private var showAddRequest = false
    @State private var selectedStatus: String = "全部"
    private let statuses = ["全部", "待審核", "已核准", "已駁回"]

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var filteredRequests: [LeaveRequest] {
        if selectedStatus == "全部" { return requests }
        return requests.filter { $0.status.displayName == selectedStatus }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statuses, id: \.self) { status in
                        FilterChip(title: status, isSelected: selectedStatus == status) {
                            selectedStatus = status
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)

            // Pending count banner
            let pendingCount = requests.filter { $0.status == .pending }.count
            if pendingCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)
                    Text("有 \(pendingCount) 筆請假申請待審核")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
            }

            List {
                ForEach(filteredRequests) { request in
                    LeaveRequestRow(request: request, userRole: userRole, onApprove: {
                        updateStatus(request, to: .approved)
                    }, onReject: {
                        updateStatus(request, to: .rejected)
                    })
                    .listRowBackground(Color.white)
                    .listRowSeparatorTint(Color(.systemGray5))
                }
            }
            .listStyle(.plain)
        }
        .background(Color.brandBackground)
        .navigationTitle("請假管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if userRole == .caregiver {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRequest = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("申請請假")
                        }
                        .foregroundStyle(Color.brandTeal)
                        .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRequest) {
            AddLeaveRequestView { newRequest in
                requests.insert(newRequest, at: 0)
            }
        }
        .task {
            requests = (try? await service.fetchLeaveRequests()) ?? []
        }
    }

    private func updateStatus(_ request: LeaveRequest, to status: LeaveStatus) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            withAnimation {
                requests[index] = LeaveRequest(
                    id: request.id,
                    type: request.type,
                    startDate: request.startDate,
                    endDate: request.endDate,
                    reason: request.reason,
                    status: status
                )
            }
        }
    }
}

// MARK: - Leave Request Row
struct LeaveRequestRow: View {
    let request: LeaveRequest
    let userRole: UserRole
    let onApprove: () -> Void
    let onReject: () -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Type tag
                Text(request.typeDisplayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.brandTeal))

                Spacer()

                // Status
                Text(request.status.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(request.status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(request.status.color.opacity(0.12)))
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandTeal)
                Text("\(dateFormatter.string(from: request.startDate)) – \(dateFormatter.string(from: request.endDate))")
                    .font(.system(size: 14, weight: .medium))
            }

            if !request.reason.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(request.reason)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons (only for pending, family can approve/reject)
            if request.status == .pending && userRole == .family {
                HStack(spacing: 12) {
                    Button(action: onReject) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text("拒絕")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(.red, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                            Text("核准")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.brandTeal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Leave Request View
struct AddLeaveRequestView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (LeaveRequest) -> Void

    @State private var leaveType = "事假"
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400)
    @State private var reason = ""
    private let types = ["事假", "病假", "緊急"]

    var body: some View {
        NavigationStack {
            Form {
                Section("假別") {
                    Picker("假別", selection: $leaveType) {
                        ForEach(types, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("日期") {
                    DatePicker("開始日期", selection: $startDate, displayedComponents: .date)
                    DatePicker("結束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("原因") {
                    TextEditor(text: $reason)
                        .frame(height: 100)
                }
            }
            .navigationTitle("請假申請")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("提交") {
                        let req = LeaveRequest(
                            id: UUID().uuidString,
                            type: leaveType,
                            startDate: startDate,
                            endDate: endDate,
                            reason: reason,
                            status: .pending
                        )
                        onAdd(req)
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LeaveManagementView()
    }
}
