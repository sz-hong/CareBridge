import SwiftUI
import Charts

// MARK: - Brand Color
extension Color {
    static let brandTeal = Color(red: 0.0, green: 0.50, blue: 0.55)
    static let brandTealLight = Color(red: 0.82, green: 0.94, blue: 0.95)
    static let brandBackground = Color(red: 0.94, green: 0.97, blue: 0.98)
}

// Destinations pushed from HomeView. Value-based NavigationLink lets the
// outer NavigationStack track depth via its path binding (so SOS can hide).
enum HomeDestination: Hashable {
    case health
}

// MARK: - HomeView
struct HomeView: View {
    @Binding var showProfile: Bool
    @Binding var isInHomeDetail: Bool
    let userRole: UserRole
    let previewedPhotoID: String?
    let onPreviewPhoto: (PhotoPreviewItem) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(UserStore.self) private var userStore
    @Environment(LocaleStore.self) private var localeStore
    @Environment(MedicationStore.self) private var medicationStore
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(TodoStore.self) private var todoStore
    @Environment(TodaySummaryStore.self) private var todaySummaryStore
    @Environment(\.dataService) private var service
    @Environment(\.scenePhase) private var scenePhase
    // 即時讀取本機 HealthKit 數值（與健康監測頁共用同一個 manager）。
    // 沒有實際讀數時為 nil —— 首頁一律顯示「—」而非捏造的假值。
    @State private var healthKit = HealthKitManager()
    @State private var showNotifications = false
    @State private var navPath = NavigationPath()
    @State private var liveSocket = HealthLiveSocket()

    /// 下一劑尚未服用的藥物時間字串
    private var nextDoseDescription: String {
        let cal = Calendar.current
        let now = Date()
        let curMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let upcoming = medicationStore.doses.first {
            !$0.isDone && timeStringToMinutes($0.time) > curMins
        }
        guard let d = upcoming else {
            return medicationStore.doses.isEmpty ? localized("暫無藥物") : localized("今日完成")
        }
        return localizedNextDose(time: d.time)
    }

    private func timeStringToMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    /// Most recent blood-pressure reading from the care log. Falls back to
    /// regex-parsing `detail` for entries saved before the structured fields
    /// were introduced.
    private var latestBloodPressure: (systolic: Int, diastolic: Int, at: Date)? {
        let vitals = careLogStore.entries
            .filter { $0.type == .vital }
            .sorted { $0.timestamp > $1.timestamp }
        for entry in vitals {
            if let s = entry.bloodPressureSystolic, let d = entry.bloodPressureDiastolic {
                return (s, d, entry.timestamp)
            }
            if let match = entry.detail.range(of: #"(\d{2,3})\s*/\s*(\d{2,3})"#, options: .regularExpression) {
                let parts = entry.detail[match].split(separator: "/").map {
                    Int($0.trimmingCharacters(in: .whitespaces)) ?? 0
                }
                if parts.count == 2, parts[0] > 0, parts[1] > 0 {
                    return (parts[0], parts[1], entry.timestamp)
                }
            }
        }
        return nil
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $navPath) {
                ScrollView {
                    homeContent
                }
                .background(Color.brandBackground)
                .scrollIndicators(.hidden)
                .refreshable {
                    medicationStore.load()
                    await careLogStore.refreshRecentEntries()
                    todoStore.load()
                    await healthKit.loadLatestValues()
                    await seedBackendHealthDataIfNeeded(overwriteExisting: true)
                }
                .navigationDestination(for: HomeDestination.self) { dest in
                    switch dest {
                    case .health:     HealthMonitorView()
                    }
                }
                .navigationDestination(isPresented: $showNotifications) {
                    NotificationCenterView()
                }
                .onChange(of: navPath.count) { _, newCount in
                    isInHomeDetail = newCount > 0
                }
                .onChange(of: showNotifications) { _, isShown in
                    isInHomeDetail = isShown || navPath.count > 0
                }
                .task {
                    medicationStore.load()
                    await careLogStore.refreshRecentEntries()
                    todoStore.load()

                    // 1) 本機 HealthKit 即時讀數（看護／長者端有配對 Apple Watch 時）。
                    await healthKit.requestAuthorization()

                    // 2) 後端 dashboard 補上遠端家屬看不到本機 HealthKit 的情況
                    //    （資料是別的家庭成員上傳、經後端轉發的真實讀數）。
                    //    只在本機沒有讀數時用後端值 seed，避免覆蓋更即時的本機數據。
                    await seedBackendHealthDataIfNeeded(overwriteExisting: false)


                    // 3) Live updates：任何家庭成員上傳 HealthKit 後，後端會即時
                    //    透過 WebSocket 推送，這裡把心率／血氧更新到卡片上。
                    liveSocket.onUpdate = { update in
                        applyLiveUpdate(update)
                    }
                    liveSocket.connect()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        medicationStore.load()
                        todoStore.load()
                        liveSocket.reconnectIfNeeded()
                        Task {
                            await careLogStore.refreshRecentEntries()
                            await healthKit.loadLatestValues()
                            await seedBackendHealthDataIfNeeded(overwriteExisting: true)
                        }
                    }
                }
                .onDisappear { liveSocket.disconnect() }
            }
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if usesWideLayout {
            VStack(spacing: 24) {
                greetingSection
                quickSummaryCard

                healthStatusCard

                HStack(alignment: .top, spacing: 20) {
                    todayPhotoAlbumCard
                    todayTasksCard
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 20) {
                greetingSection
                quickSummaryCard

                healthStatusCard

                // Photos captured in today's care logs
                todayPhotoAlbumCard

                // Today's Tasks
                todayTasksCard

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: localeStore.locale)
    }

    private func localizedNextDose(time: String) -> String {
        switch localeStore.code {
        case "vi": return "Tiếp theo: \(time)"
        default:   return "下一次：\(time)"
        }
    }

    private func localizedSummaryCount(_ count: Int, zhUnit: String, viUnit: String) -> String {
        switch localeStore.code {
        case "vi": return "\(count) \(viUnit)"
        default:   return "\(count) \(zhUnit)"
        }
    }

    private func applyLiveUpdate(_ update: HealthLiveUpdate) {
        for point in update.points {
            switch point.type {
            case "heart_rate":   healthKit.heartRate = point.value
            case "blood_oxygen": healthKit.bloodOxygen = point.value
            default: break
            }
        }
    }

    private func seedBackendHealthDataIfNeeded(overwriteExisting: Bool) async {
        if let backend = try? await service.fetchHealthData(elderId: "") {
            if overwriteExisting || healthKit.heartRate == nil, backend.heartRate > 0 {
                healthKit.heartRate = Double(backend.heartRate)
            }
            if overwriteExisting || healthKit.bloodOxygen == nil, backend.bloodOxygen > 0 {
                healthKit.bloodOxygen = backend.bloodOxygen
            }
        }
    }

    // MARK: - Vital Status (依實際數值計算，無資料回傳中性灰)

    /// 心率狀態徽章。無讀數時顯示「—」。
    private var heartRateStatus: (text: String, color: Color) {
        guard let bpm = healthKit.heartRate.map({ Int($0) }) else { return ("—", .secondary) }
        if bpm > 100 { return ("HIGH", .orange) }
        if bpm < 55  { return ("LOW", .orange) }
        return ("STABLE", .green)
    }

    /// 血氧狀態徽章。無讀數時顯示「—」。
    private var bloodOxygenStatus: (text: String, color: Color) {
        guard let spo2 = healthKit.bloodOxygen else { return ("—", .secondary) }
        if spo2 < 94  { return ("LOW", .orange) }
        if spo2 >= 98 { return ("OPTIMAL", .green) }
        return ("NORMAL", .green)
    }

    /// 血壓狀態徽章（取自照護日誌最新讀數）。未量測時顯示「—」。
    private var bloodPressureStatus: (text: String, color: Color) {
        guard let bp = latestBloodPressure else { return ("—", .secondary) }
        if bp.systolic >= 140 || bp.diastolic >= 90 { return ("HIGH", .orange) }
        if bp.systolic < 90 || bp.diastolic < 60 { return ("LOW", .orange) }
        return ("NORMAL", .green)
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        RootPageHeader(horizontalPadding: 0) {
            showNotifications = true
        } title: {
            Text(greetingText)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var greetingText: String {
        let name = userStore.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let greeting: String
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            greeting = localizedGreeting(.morning)
        case 12..<14:
            greeting = localizedGreeting(.noon)
        case 14..<18:
            greeting = localizedGreeting(.afternoon)
        default:
            greeting = localizedGreeting(.night)
        }
        return name.isEmpty ? greeting : "\(greeting)\(greetingSeparator)\(name)"
    }

    private enum GreetingPeriod {
        case morning
        case noon
        case afternoon
        case night
    }

    private var greetingSeparator: String {
        localeStore.code == "zh-TW" ? "，" : ", "
    }

    private func localizedGreeting(_ period: GreetingPeriod) -> String {
        switch localeStore.code {
        case "id":
            switch period {
            case .morning: return "Selamat pagi"
            case .noon: return "Selamat siang"
            case .afternoon: return "Selamat sore"
            case .night: return "Selamat malam"
            }
        case "vi":
            switch period {
            case .morning: return "Chào buổi sáng"
            case .noon: return "Chào buổi trưa"
            case .afternoon: return "Chào buổi chiều"
            case .night: return "Chào buổi tối"
            }
        case "tl":
            switch period {
            case .morning: return "Magandang umaga"
            case .noon: return "Magandang tanghali"
            case .afternoon: return "Magandang hapon"
            case .night: return "Magandang gabi"
            }
        default:
            switch period {
            case .morning: return "早安"
            case .noon: return "午安"
            case .afternoon: return "下午好"
            case .night: return "晚安"
            }
        }
    }

    private var quickSummaryCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("快速摘要")
                    .font(.system(size: 17, weight: .bold))

                if let summary = todaySummaryStore.summary {
                    Text(summary.summary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    HStack(spacing: 12) {
                        summarySourceLabel(
                            icon: "doc.text",
                            value: localizedSummaryCount(
                                summary.sourceCounts.careLogs,
                                zhUnit: "筆日誌",
                                viUnit: "nhật ký"
                            )
                        )
                        if let todos = summary.sourceCounts.todos {
                            summarySourceLabel(
                                icon: "checklist",
                                value: localizedSummaryCount(
                                    todos,
                                    zhUnit: "個待辦",
                                    viUnit: "việc cần làm"
                                )
                            )
                        }
                        if let medications = summary.sourceCounts.medications {
                            summarySourceLabel(
                                icon: "pills.fill",
                                value: localizedSummaryCount(
                                    medications,
                                    zhUnit: "項用藥",
                                    viUnit: "mục thuốc"
                                )
                            )
                        }
                    }
                } else if todaySummaryStore.isLoading {
                    Text("正在整理今天的照護重點…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .redacted(reason: .placeholder)
                } else {
                    Text("目前尚無今日摘要")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private func summarySourceLabel(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
    }

    private var overallHealthStatus: (text: String, color: Color) {
        let hasAnyReading =
            healthKit.heartRate != nil ||
            healthKit.bloodOxygen != nil ||
            latestBloodPressure != nil

        guard hasAnyReading else {
            return (localized("尚無資料"), .secondary)
        }

        let hasWarning =
            heartRateStatus.text == "HIGH" ||
            heartRateStatus.text == "LOW" ||
            bloodOxygenStatus.text == "LOW" ||
            bloodPressureStatus.text == "HIGH" ||
            bloodPressureStatus.text == "LOW"

        return hasWarning ? (localized("需注意"), .orange) : (localized("正常"), .green)
    }

    private var healthStatusDetail: String {
        var parts: [String] = []

        if let heartRate = healthKit.heartRate {
            parts.append("\(localized("心率")) \(Int(heartRate)) bpm")
        }

        if let bloodOxygen = healthKit.bloodOxygen {
            parts.append("\(localized("血氧")) \(Int(bloodOxygen))%")
        }

        if let bloodPressure = latestBloodPressure {
            parts.append("\(localized("血壓")) \(bloodPressure.systolic)/\(bloodPressure.diastolic)")
        }

        return parts.isEmpty ? localized("點擊查看健康監測") : parts.joined(separator: " · ")
    }

    private var healthStatusCard: some View {
        NavigationLink(value: HomeDestination.health) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.brandTealLight)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.brandTeal)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("健康狀態")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(healthStatusDetail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(overallHealthStatus.color)
                        .frame(width: 7, height: 7)
                    Text(overallHealthStatus.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(overallHealthStatus.color)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("健康狀態")
        .accessibilityValue(overallHealthStatus.text)
        .accessibilityHint("前往健康監測")
    }

    private var todayTodos: [TodoItem] {
        todoStore.todos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return Calendar.current.isDateInToday(due)
        }
        .sorted {
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted
            }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    private var completedTodayTodoCount: Int {
        todayTodos.filter(\.isCompleted).count
    }

    private enum TaskRowText {
        case localized(LocalizedStringKey)
        case verbatim(String)
    }

    private var todayTodoStatusText: TaskRowText {
        guard !todayTodos.isEmpty else { return .localized("今日無待辦") }
        if completedTodayTodoCount == todayTodos.count { return .localized("今日待辦已完成") }
        return .verbatim(todayTodos.first(where: { !$0.isCompleted })?.title ?? "")
    }

    private var todayTodoProgressText: String {
        todayTodos.isEmpty ? "—" : "\(completedTodayTodoCount)/\(todayTodos.count)"
    }

    private var medicationProgressText: String {
        medicationStore.totalCount == 0
            ? "—"
            : "\(medicationStore.takenCount)/\(medicationStore.totalCount)"
    }

    private var todayPhotoEntries: [CareLogEntry] {
        careLogStore.entries
            .filter {
                Calendar.current.isDateInToday($0.timestamp)
                    && $0.photoURL != nil
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Today's Tasks
    private var todayTasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日處理事項")
                .font(.system(size: 17, weight: .bold))

            taskRow(
                icon: "checkmark.circle.fill",
                title: "今日待辦",
                subtitle: todayTodoStatusText,
                primaryValue: todayTodoProgressText,
                secondaryValue: "完成"
            )

            taskRow(
                icon: "pills.fill",
                title: "用藥",
                subtitle: .verbatim(nextDoseDescription),
                primaryValue: medicationProgressText,
                secondaryValue: "已服用"
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private var todayPhotoAlbumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日相冊")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Text("\(todayPhotoEntries.count) 張")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if todayPhotoEntries.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.brandTeal)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.brandTealLight)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("今天還沒有照片")
                            .font(.system(size: 15, weight: .semibold))
                        Text("新增照護日誌時可選擇拍照")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(todayPhotoEntries) { entry in
                            todayPhotoThumbnail(entry)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private func todayPhotoThumbnail(_ entry: CareLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let photoURL = entry.photoURL {
                CachedRemotePhoto(url: photoURL) { image in
                    PreviewablePhotoSource(
                        id: "home-photo-\(entry.id)",
                        image: image,
                        sourceCornerRadius: 10,
                        isPreviewed: previewedPhotoID == "home-photo-\(entry.id)",
                        onPreview: onPreviewPhoto
                    ) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 132, height: 96)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .accessibilityLabel("預覽今日相冊照片")
                    .accessibilityHint("點兩下放大照片")
                } placeholder: {
                    albumPlaceholder(systemImage: "photo")
                        .frame(width: 132, height: 96)
                        .clipShape(.rect(cornerRadius: 10))
                }
            }

            Text(entry.type.displayName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 132, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(entry.type.displayName))
        .accessibilityValue(
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
        )
    }

    private func albumPlaceholder(systemImage: String) -> some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }

    /// Shared status row used by 今日待辦 / 用藥. These rows are deliberately
    /// non-navigational; the actual entry points now live in 照護日誌.
    private func taskRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: TaskRowText,
        primaryValue: String,
        secondaryValue: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.brandTealLight)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: icon)
                        .foregroundStyle(Color.brandTeal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                taskRowText(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(primaryValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.brandTeal)
                Text(secondaryValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
    }

    @ViewBuilder
    private func taskRowText(_ text: TaskRowText) -> some View {
        switch text {
        case .localized(let key):
            Text(key)
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }

}

#Preview {
    HomePreviewHost()
}

private struct HomePreviewHost: View {
    var body: some View {
        let svc = MockDataService()
        HomeView(
            showProfile: .constant(false),
            isInHomeDetail: .constant(false),
            userRole: .family,
            previewedPhotoID: nil,
            onPreviewPhoto: { _ in }
        )
        .environment(MedicationStore(service: svc))
        .environment(CareLogStore(service: svc))
        .environment(CalendarStore(service: svc))
        .environment(TodoStore(service: svc))
        .environment(UserStore(service: svc))
        .environment(NotificationStore(service: svc))
        .environment(TodaySummaryStore(service: svc))
    }
}
