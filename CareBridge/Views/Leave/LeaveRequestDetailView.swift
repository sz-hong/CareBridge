import SwiftUI

/// 請假申請詳情頁 — 從聊天室卡片點入
/// 看護：查看自己的申請狀態與家屬投票結果
/// 家屬：投票「有空」或「沒空」
///       全部家屬都「沒空」→ 自動拒絕
struct LeaveRequestDetailView: View {
    let requestId: String
    let userRole: UserRole
    @Environment(\.dataService) private var service
    @Environment(UserStore.self) private var userStore
    @State private var request: LeaveRequest?
    @State private var isLoading = true
    @State private var hasVoted = false

    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d（E）"; f.locale = Locale(identifier: "zh-TW"); return f
    }()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("載入中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let req = request {
                ScrollView {
                    VStack(spacing: 16) {
                        leaveInfoCard(req)
                        votingSection(req)
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("找不到此請假申請", systemImage: "calendar")
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("請假申請")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRequest() }
    }

    // MARK: - Leave Info Card
    private func leaveInfoCard(_ req: LeaveRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text(req.typeDisplayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.brandTeal))
                Spacer()
                Text(req.status.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(req.status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(req.status.color.opacity(0.12)))
            }

            // Applicant
            if let name = req.applicantName {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.brandTeal)
                    Text("申請人：\(name)")
                        .font(.system(size: 14, weight: .medium))
                }
            }

            // Date range
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandTeal)
                Text("\(dateFmt.string(from: req.startDate)) — \(dateFmt.string(from: req.endDate))")
                    .font(.system(size: 15, weight: .medium))
            }

            // Duration
            let days = max(1, Calendar.current.dateComponents([.day], from: req.startDate, to: req.endDate).day ?? 1)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandTeal)
                Text("共 \(days) 天")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            // Reason
            if !req.reason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("請假原因")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(req.reason)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Voting Section
    private func votingSection(_ req: LeaveRequest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("家屬回覆")
                .font(.system(size: 17, weight: .bold))

            // If this leave was already resolved (status != pending), show
            // an outcome banner instead of the per-member vote roster — the
            // "尚未回覆" placeholder would be misleading because voting is
            // closed regardless of whether anyone voted.
            if req.status != .pending {
                resolvedBanner(req)
            } else {
                voteRoster(req)
            }

            // Current family user voting buttons
            if req.status == .pending && userRole == .family {
                let myId = userStore.currentUser?.id ?? ""
                let alreadyVoted = (req.votes ?? []).contains { $0.memberId == myId }

                if alreadyVoted || hasVoted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("您已完成投票")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    VStack(spacing: 8) {
                        Text("看護請假期間，您是否有空照顧？")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                Task { await vote(leaveId: req.id, isAvailable: false) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle")
                                    Text("我沒空")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12).stroke(.red, lineWidth: 1.5))
                            }

                            Button {
                                Task { await vote(leaveId: req.id, isAvailable: true) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                    Text("我有空")
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
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Resolved Banner (status != pending)
    @ViewBuilder
    private func resolvedBanner(_ req: LeaveRequest) -> some View {
        let approved = req.status == .approved
        HStack(spacing: 10) {
            Image(systemName: approved ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.system(size: 22))
                .foregroundStyle(approved ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(approved ? "此申請已核准" : "此申請已拒絕")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(approved ? .green : .red)
                Text("投票已結束，無需再回覆")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((approved ? Color.green : .red).opacity(0.08))
        )

        // If any votes were recorded, show them as a read-only history
        let votes = req.votes ?? []
        if !votes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("投票紀錄")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(votes) { vote in
                    HStack(spacing: 8) {
                        Image(systemName: vote.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(vote.isAvailable ? .green : .red)
                        Text(vote.memberName)
                            .font(.system(size: 14))
                        Spacer()
                        Text(vote.isAvailable ? "有空" : "沒空")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Vote Roster (status == pending)
    @ViewBuilder
    private func voteRoster(_ req: LeaveRequest) -> some View {
        let votes = req.votes ?? []
        let familyMembers = userStore.familyMembers.filter { $0.role == .family }

        if familyMembers.isEmpty && votes.isEmpty {
            Text("尚無家屬成員")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        } else {
            ForEach(familyMembers) { member in
                let vote = votes.first { $0.memberId == member.id }
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.brandTealLight)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.brandTeal)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 15, weight: .medium))
                        if let vote {
                            Text(vote.isAvailable ? "有空 ✓" : "沒空 ✗")
                                .font(.system(size: 13))
                                .foregroundStyle(vote.isAvailable ? .green : .red)
                        } else {
                            Text("尚未回覆")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if let vote {
                        Image(systemName: vote.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(vote.isAvailable ? .green : .red)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
            }

            if !votes.isEmpty {
                let allVoted = votes.count >= familyMembers.count && !familyMembers.isEmpty
                let allUnavailable = allVoted && votes.allSatisfy { !$0.isAvailable }
                let anyAvailable = votes.contains { $0.isAvailable }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: allUnavailable ? "xmark.octagon.fill" : (anyAvailable ? "checkmark.seal.fill" : "hourglass"))
                        .foregroundStyle(allUnavailable ? .red : (anyAvailable ? .green : .orange))
                    Text(allUnavailable ? "所有家屬皆沒空，請假被拒絕"
                         : anyAvailable ? "有家屬表示有空，請假核准中"
                         : "等待家屬回覆中…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(allUnavailable ? .red : (anyAvailable ? .green : .orange))
                }
            }
        }
    }

    // MARK: - Actions
    private func loadRequest() async {
        isLoading = true
        userStore.load()
        let all = (try? await service.fetchLeaveRequests()) ?? []
        request = all.first { $0.id == requestId }
        isLoading = false
    }

    private func vote(leaveId: String, isAvailable: Bool) async {
        if let updated = try? await service.voteLeave(id: leaveId, isAvailable: isAvailable) {
            withAnimation { request = updated; hasVoted = true }
        } else {
            // Optimistic: add local vote
            let myId = userStore.currentUser?.id ?? ""
            let myName = userStore.currentUser?.name ?? ""
            let newVote = LeaveVote(id: UUID().uuidString, memberId: myId, memberName: myName, isAvailable: isAvailable, votedAt: Date())
            withAnimation {
                request?.votes = (request?.votes ?? []) + [newVote]
                hasVoted = true
            }
        }
    }
}
