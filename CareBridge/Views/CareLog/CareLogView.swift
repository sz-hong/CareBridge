import SwiftUI

struct CareLogView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    @Environment(CareLogStore.self) private var careLogStore
    @State private var selectedFilter: CareLogType? = nil
    @State private var showAddEntry = false
    @State private var showNotifications = false
    @State private var calendarMode = 0          // 0 = 週, 1 = 月
    @State private var selectedDate = Date()

    private let calendar = Calendar.current

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM月dd日 EEEE"
        f.locale = Locale(identifier: "zh-TW")
        return f
    }()

    var filteredEntries: [CareLogEntry] {
        let sameDayEntries = careLogStore.entries.filter {
            calendar.isDate($0.timestamp, inSameDayAs: selectedDate)
        }
        guard let filter = selectedFilter else { return sameDayEntries }
        return sameDayEntries.filter { $0.type == filter }
    }

    var groupedEntries: [(String, [CareLogEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        return groups.sorted { $0.key > $1.key }.map { (dateFormatter.string(from: $0.key), $0.value) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter chips + calendar header
                headerSection

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        if careLogStore.isLoading && careLogStore.entries.isEmpty {
                            ProgressView()
                                .padding(.top, 32)
                        }

                        if let errorMessage = careLogStore.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }

                        ForEach(groupedEntries, id: \.0) { dateString, dayEntries in
                            VStack(alignment: .leading, spacing: 0) {
                                // Date header
                                Text("TODAY  \(dateString)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)

                                // Timeline entries
                                ForEach(dayEntries) { entry in
                                    TimelineEntryRow(entry: entry)
                                }
                            }
                        }
                        Spacer(minLength: 32)
                    }
                }
                .background(Color.brandBackground)
            }
            .background(Color.brandBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.brandTeal)
                            Text("CareBridge")
                                .font(.system(size: 20, weight: .bold))
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
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showAddEntry = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.brandTeal)
                            .frame(width: 52, height: 52)
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .sheet(isPresented: $showAddEntry) {
                AddCareLogView(userRole: userRole) { newEntry in
                    careLogStore.addEntry(newEntry)
                }
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .task { careLogStore.load() }
        }
    }

    // MARK: - Header with filter + calendar
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Page title
            HStack {
                Text("照護日誌")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "All", isSelected: selectedFilter == nil) {
                        selectedFilter = nil
                    }
                    ForEach(CareLogType.allCases, id: \.self) { type in
                        FilterChip(title: type.displayName, isSelected: selectedFilter == type) {
                            selectedFilter = (selectedFilter == type) ? nil : type
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            // 行事曆 header row: title + prev/next + 週/月 toggle
            calendarHeader

            // Calendar body (switches between week strip and month grid)
            miniCalendar

            // Event dot legend
            calendarLegend

            Divider()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Calendar header row
    private var calendarHeader: some View {
        HStack {
            Text("行事曆")
                .font(.system(size: 15, weight: .bold))

            Spacer()

            // prev / next month (or week)
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedDate = calendarMode == 0
                        ? (calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate)
                        : (calendar.date(byAdding: .month,      value: -1, to: selectedDate) ?? selectedDate)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 28, height: 28)
            }

            Text(calendarTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .center)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedDate = calendarMode == 0
                        ? (calendar.date(byAdding: .weekOfYear, value: +1, to: selectedDate) ?? selectedDate)
                        : (calendar.date(byAdding: .month,      value: +1, to: selectedDate) ?? selectedDate)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brandTeal)
                    .frame(width: 28, height: 28)
            }

            // 週 / 月 toggle
            HStack(spacing: 0) {
                ForEach(["週", "月"].indices, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { calendarMode = i }
                    } label: {
                        Text(["週", "月"][i])
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 36, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(calendarMode == i ? Color.brandTeal : Color.clear)
                            )
                            .foregroundStyle(calendarMode == i ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(.systemGray5)))
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var calendarTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh-TW")
        fmt.dateFormat = calendarMode == 0 ? "M月" : "yyyy年M月"
        return fmt.string(from: selectedDate)
    }

    // MARK: - Calendar body
    private var miniCalendar: some View {
        let weekDays = ["日", "一", "二", "三", "四", "五", "六"]

        return VStack(spacing: 0) {
            // Day-of-week header
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            if calendarMode == 0 {
                // ── WEEK strip ──
                weekStrip
            } else {
                // ── MONTH grid ──
                monthGrid
            }
        }
    }

    // Week mode: 7 days centred on selectedDate
    private var weekStrip: some View {
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        ) ?? selectedDate
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayCell(date: day)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    // Month mode: full calendar grid
    private var monthGrid: some View {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedDate)
        ) ?? selectedDate
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? (1..<31)
        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1 // 0-indexed
        let allCells: [Date?] = Array(repeating: nil, count: firstWeekday)
            + range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(allCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date: date)
                } else {
                    Color.clear.frame(height: 36)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private func dayCell(date: Date) -> some View {
        let isToday    = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let hasEntry   = careLogStore.entries.contains { calendar.isDate($0.timestamp, inSameDayAs: date) }

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedDate = date
                if calendarMode == 1 { calendarMode = 0 }   // 月 → 自動縮回週
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if isSelected {
                        Circle().fill(Color.brandTeal).frame(width: 30, height: 30)
                    } else if isToday {
                        Circle().stroke(Color.brandTeal, lineWidth: 1.5).frame(width: 30, height: 30)
                    }
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: isSelected || isToday ? .bold : .regular))
                        .foregroundStyle(isSelected ? .white : isToday ? Color.brandTeal : .primary)
                }
                // entry dot
                Circle()
                    .fill(hasEntry ? Color.brandTeal : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legend
    private var calendarLegend: some View {
        HStack(spacing: 16) {
            ForEach([("藥物", Color.brandTeal), ("醫療", Color.red),
                     ("急診", Color.orange), ("個人", Color.blue)], id: \.0) { label, color in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    /// Convenience initializer to accept plain String (from enum displayName etc.)
    /// and convert it to LocalizedStringKey for lookup.
    init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = LocalizedStringKey(title)
        self.isSelected = isSelected
        self.action = action
    }

    init(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.brandTeal : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline Entry Row
struct TimelineEntryRow: View {
    let entry: CareLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time column
            VStack(spacing: 0) {
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60)
                    .padding(.top, 16)
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }

            // Dot
            ZStack {
                Circle()
                    .fill(entry.type.uiColor)
                    .frame(width: 10, height: 10)
            }
            .padding(.top, 18)
            .padding(.horizontal, 8)

            // Card
            VStack(alignment: .leading, spacing: 0) {
                logEntryCard
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, 16)
            }
        }
    }

    private var logEntryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge
            HStack(spacing: 6) {
                Text(entry.type.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(entry.type.uiColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .stroke(entry.type.uiColor, lineWidth: 1)
                    )
                Spacer()
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(entry.title)
                .font(.system(size: 15, weight: .semibold))

            // Detail grid for vital signs
            if entry.type == .vital {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOOD\nPRESSURE")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(bloodPressureText)
                            .font(.system(size: 20, weight: .bold))
                        Text("mmHg")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("BLOOD\nSUGAR")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(bloodSugarText)
                            .font(.system(size: 20, weight: .bold))
                        Text("mmol/L")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                }
                if let extra = extraVitalsText {
                    Text(extra)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(entry.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if entry.type == .medication {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                    Text("已服用")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white))
    }

    // MARK: - Vital parsing

    /// Blood pressure — prefer structured fields, fall back to regex-parsing detail.
    private var bloodPressureText: String {
        if let s = entry.bloodPressureSystolic, let d = entry.bloodPressureDiastolic {
            return "\(s)/\(d)"
        }
        if let m = entry.detail.range(of: #"(\d{2,3})\s*/\s*(\d{2,3})"#, options: .regularExpression) {
            return entry.detail[m]
                .replacingOccurrences(of: " ", with: "")
        }
        return "—/—"
    }

    /// Blood sugar — prefer structured field, fall back to regex on detail.
    private var bloodSugarText: String {
        if let bs = entry.bloodSugar {
            return String(format: "%.1f", bs)
        }
        if let m = entry.detail.range(of: #"血糖\s*(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let raw = entry.detail[m]
                .replacingOccurrences(of: "血糖", with: "")
                .trimmingCharacters(in: .whitespaces)
            return raw.isEmpty ? "—" : raw
        }
        return "—"
    }

    /// 體重 / 體溫等其他 vitals 的補充文字（去除已在卡片裡顯示的血壓、血糖
    /// 與重複的格式化欄位以避免兩行雷同）。靠 dedupe 把同義字串合併。
    private var extraVitalsText: String? {
        let parts = entry.detail
            .components(separatedBy: "｜")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !$0.contains("血壓") && !$0.contains("血糖") }

        // dedupe 但保留順序
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        let text = unique.joined(separator: "｜")
        return text.isEmpty ? nil : text
    }
}

// MARK: - Add Care Log View
struct AddCareLogView: View {
    @Environment(\.dismiss) private var dismiss
    let userRole: UserRole
    let onAdd: (CareLogEntry) -> Void

    @State private var selectedType: CareLogType = .vital  // 預設改為生理數值（移除備註後）
    @State private var recordDate = Date()

    // vital signs
    @State private var bp_systolic = ""
    @State private var bp_diastolic = ""
    @State private var weight = ""              // kg, 選填
    @State private var bloodSugar = ""          // mmol/L, 選填
    @State private var temperature = ""         // °C, 選填

    // medication
    @State private var medName = ""
    @State private var medDosage = ""
    @State private var medRoute = 0             // 0=口服, 1=外用, 2=注射
    @State private var medTaken = true

    // meal
    @State private var mealType = 0             // 0=早餐, 1=午餐, 2=晚餐, 3=點心
    @State private var mealDesc = ""
    @State private var appetite = 1             // 0=差, 1=一般, 2=良好

    // activity
    @State private var activityName = ""
    @State private var activityDuration = ""
    @State private var activityIntensity = 1    // 0=輕度, 1=中度, 2=高強度

    // note
    @State private var noteText = ""

    private let routeLabels     = ["口服", "外用", "注射"]
    private let mealLabels      = ["早餐", "午餐", "晚餐", "點心"]
    private let appetiteLabels  = ["差", "一般", "良好"]
    private let intensityLabels = ["輕度", "中度", "高強度"]
    // (conditionLabels removed — vital section is now optional fields only)

    private var availableRecordTypes: [CareLogType] {
        // 「備註」類型已由 chat / Todo 取代，新增紀錄時不再提供。
        CareLogType.allCases.filter { $0 != .note }
    }

    var body: some View {
        NavigationStack {
            Form {
                recordForm
            }
            .navigationTitle("新增紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { saveEntry() }
                        .fontWeight(.semibold)
                        .tint(Color.brandTeal)
                }
            }
        }
    }

    // MARK: - 紀錄 Form
    @ViewBuilder
    private var recordForm: some View {
        Section("記錄類型") {
            Picker("類型", selection: $selectedType) {
                ForEach(availableRecordTypes, id: \.self) { t in
                    Label(t.displayName, systemImage: t.icon).tag(t)
                }
            }
        }

        Section("記錄時間") {
            DatePicker("時間", selection: $recordDate, displayedComponents: [.date, .hourAndMinute])
                .tint(Color.brandTeal)
        }

        switch selectedType {
        case .vital:      vitalSection
        case .medication: medicationSection
        case .meal:       mealSection
        case .activity:   activitySection
        case .note:       noteSection
        }
    }

    // MARK: - 生理 section
    @ViewBuilder
    private var vitalSection: some View {
        // 全部欄位 optional — 使用者只填關心的就好。
        // 心率與血氧由 Apple Watch 自動同步，不在這裡填。
        Section {
            Text("以下欄位皆為選填，可只填要記錄的項目")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }

        Section("血壓 (mmHg)") {
            HStack {
                Text("收縮壓")
                Spacer()
                TextField("120", text: $bp_systolic)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
            HStack {
                Text("舒張壓")
                Spacer()
                TextField("80", text: $bp_diastolic)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
        }

        Section("體重 (kg)") {
            HStack {
                Text("體重")
                Spacer()
                TextField("60.5", text: $weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }

        Section("血糖 (mmol/L)") {
            HStack {
                Text("血糖")
                Spacer()
                TextField("5.6", text: $bloodSugar)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }

        Section("體溫 (°C)") {
            HStack {
                Text("體溫")
                Spacer()
                TextField("36.5", text: $temperature)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        }
    }

    // MARK: - 用藥 section
    @ViewBuilder
    private var medicationSection: some View {
        Section("藥物資訊") {
            TextField("藥品名稱", text: $medName)
            TextField("劑量（例：100mg）", text: $medDosage)
        }

        Section("服用方式") {
            Picker("方式", selection: $medRoute) {
                ForEach(0..<routeLabels.count, id: \.self) { i in
                    Text(routeLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
        }

        Section {
            Toggle("已服用", isOn: $medTaken)
                .tint(Color.brandTeal)
        }
    }

    // MARK: - 飲食 section
    @ViewBuilder
    private var mealSection: some View {
        Section("餐別") {
            Picker("餐別", selection: $mealType) {
                ForEach(0..<mealLabels.count, id: \.self) { i in
                    Text(mealLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("飲食內容") {
            TextField("餐點描述", text: $mealDesc, axis: .vertical)
                .lineLimit(3...5)
        }

        Section("食慾") {
            Picker("食慾", selection: $appetite) {
                ForEach(0..<appetiteLabels.count, id: \.self) { i in
                    Text(appetiteLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 活動 section
    @ViewBuilder
    private var activitySection: some View {
        Section("活動資訊") {
            TextField("活動名稱（例：散步、復健）", text: $activityName)
            HStack {
                Text("時長")
                Spacer()
                TextField("30", text: $activityDuration)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("分鐘").foregroundStyle(.secondary)
            }
        }

        Section("強度") {
            Picker("強度", selection: $activityIntensity) {
                ForEach(0..<intensityLabels.count, id: \.self) { i in
                    Text(intensityLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 備註 section
    @ViewBuilder
    private var noteSection: some View {
        Section("備註內容") {
            TextField("輸入備註...", text: $noteText, axis: .vertical)
                .lineLimit(5...10)
        }
    }

    // MARK: - Save
    private func saveEntry() {
        let title: String
        let detail: String
        let type = selectedType

        switch selectedType {
        case .vital:
            title = "生理數值紀錄"
            var parts: [String] = []
            if !bp_systolic.isEmpty && !bp_diastolic.isEmpty {
                parts.append("血壓 \(bp_systolic)/\(bp_diastolic) mmHg")
            }
            if !weight.isEmpty      { parts.append("體重 \(weight) kg") }
            if !bloodSugar.isEmpty  { parts.append("血糖 \(bloodSugar) mmol/L") }
            if !temperature.isEmpty { parts.append("體溫 \(temperature)°C") }
            detail = parts.isEmpty ? "未填寫" : parts.joined(separator: "｜")
        case .medication:
            title  = medName.isEmpty ? "用藥紀錄" : "\(medName) \(medDosage)"
            detail = "\(routeLabels[medRoute])｜\(medTaken ? "已服用" : "未服用")"
        case .meal:
            title  = mealLabels[mealType]
            detail = "\(mealDesc)｜食慾：\(appetiteLabels[appetite])"
        case .activity:
            title  = activityName.isEmpty ? "活動紀錄" : activityName
            detail = "\(activityDuration.isEmpty ? "—" : activityDuration)分鐘｜\(intensityLabels[activityIntensity])"
        case .note:
            title  = "備註"
            detail = noteText
        }

        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: type,
            title: title,
            detail: detail,
            timestamp: recordDate,
            hasPhoto: false,
            bloodPressureSystolic:  selectedType == .vital ? Int(bp_systolic)  : nil,
            bloodPressureDiastolic: selectedType == .vital ? Int(bp_diastolic) : nil,
            bloodSugar:  selectedType == .vital ? Double(bloodSugar)  : nil,
            temperature: selectedType == .vital ? Double(temperature) : nil,
            weight:      selectedType == .vital ? Double(weight)      : nil
        )
        onAdd(entry)
        dismiss()
    }
}

#Preview {
    CareLogView(showProfile: .constant(false), userRole: .family)
        .environment(CareLogStore())
}

#Preview("新增") {
    AddCareLogView(userRole: .caregiver) { _ in }
        .environment(CareLogStore())
}
