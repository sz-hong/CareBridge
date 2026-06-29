import SwiftUI

struct LeaveManagementView: View {
    var userRole: UserRole = .family
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dataService) private var service
    @State private var requests: [LeaveRequest] = []
    @State private var showAddRequest = false
    @State private var selectedStatus: String = "全部"
    @State private var isReloading = false
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
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .frame(maxWidth: usesWideLayout ? 900 : .infinity)
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
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .frame(maxWidth: usesWideLayout ? 900 : .infinity)
            }

            List {
                ForEach(filteredRequests) { request in
                    NavigationLink {
                        LeaveRequestDetailView(requestId: request.id, userRole: userRole)
                    } label: {
                        LeaveRequestRow(request: request, userRole: userRole, onApprove: {
                            updateStatus(request, to: .approved)
                        }, onReject: {
                            updateStatus(request, to: .rejected)
                        })
                    }
                    .listRowBackground(Color.white)
                    .listRowSeparatorTint(Color(.systemGray5))
                }
            }
            .listStyle(.plain)
            .frame(maxWidth: usesWideLayout ? 900 : .infinity)
            .frame(maxWidth: .infinity)
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
        // Refetch every time the view appears (including pops back from
        // LeaveRequestDetailView after voting), so row status reflects any
        // server-side auto-resolution that happened in the detail flow.
        .onAppear { Task { await reload() } }
        .refreshable { await reload() }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private func reload() async {
        guard !isReloading else { return }
        isReloading = true
        defer { isReloading = false }
        if let fresh = try? await service.fetchLeaveRequests() {
            requests = fresh
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
                    status: status,
                    applicantName: request.applicantName,
                    votes: request.votes,
                    reasonTranslated: request.reasonTranslated,
                    reasonTranslations: request.reasonTranslations
                )
            }
        }
        Task { _ = try? await service.updateLeaveStatus(id: request.id, status: status) }
    }
}

// MARK: - Leave Request Row
struct LeaveRequestRow: View {
    let request: LeaveRequest
    let userRole: UserRole
    let onApprove: () -> Void
    let onReject: () -> Void
    @Environment(LocaleStore.self) private var localeStore

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
                    Text(request.displayReason(language: localeStore.code))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // Inline approve/reject removed — family members vote via the
            // detail view (有空 / 沒空) by tapping into the row.
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Leave Request View
struct AddLeaveRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onAdd: (LeaveRequest) -> Void

    @State private var leaveType = "事假"
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400)
    @State private var reason = ""
    @State private var isSubmitting = false
    private let types = ["事假", "病假", "緊急"]

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

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
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("請假申請")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("提交") {
                        Task {
                            isSubmitting = true
                            let req = LeaveRequest(
                                id: UUID().uuidString,
                                type: leaveType,
                                startDate: startDate,
                                endDate: endDate,
                                reason: reason,
                                status: .pending
                            )
                            let created = (try? await service.createLeaveRequest(req)) ?? req
                            onAdd(created)
                            dismiss()
                        }
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(isSubmitting)
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
