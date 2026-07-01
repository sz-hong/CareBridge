import SwiftUI
import PhotosUI

struct CareLogView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    let previewedPhotoID: String?
    let onPreviewPhoto: (PhotoPreviewItem) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.floatingActionBottomPadding) private var floatingActionBottomPadding
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(TodoStore.self) private var todoStore
    @Environment(MedicationStore.self) private var medicationStore
    @Environment(LocaleStore.self) private var localeStore
    @State private var selectedMode = CareLogMode.records
    @State private var selectedFilter: CareLogType? = nil
    @State private var showAddEntry = false
    @State private var showNotifications = false
    @State private var calendarMode = 0          // 0 = 週, 1 = 月
    @State private var selectedDate = Date()
    @State private var isEditingTimeline = false
    @State private var pendingCareLogDeletion: CareLogEntry?

    private let calendar = Calendar.current

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = localeStore.locale
        f.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return f
    }

    var groupedEntries: [(String, [CareLogEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: careLogStore.timelineEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        return groups.sorted { $0.key > $1.key }.map { (dateFormatter.string(from: $0.key), $0.value) }
    }

    private var timelineQueryID: String {
        let day = calendar.startOfDay(for: selectedDate)
        return "\(day.timeIntervalSince1970)-\(selectedFilter?.rawValue ?? "all")"
    }

    private var todayTodos: [TodoItem] {
        todoStore.todos.filter { todo in
            guard let dueDate = todo.dueDate else { return false }
            return calendar.isDateInToday(dueDate)
        }
        .sorted {
            if $0.isCompleted != $1.isCompleted {
                return !$0.isCompleted
            }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            careLogRoot
        }
    }

    private var careLogRoot: some View {
        careLogContent
            .background(Color.brandBackground)
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
                .padding(.trailing, usesWideLayout ? 32 : 24)
                .padding(.bottom, floatingActionBottomPadding)
            }
            .sheet(isPresented: $showAddEntry) {
                AddCareLogView(userRole: userRole) { newEntry, photo in
                    try await careLogStore.addEntry(newEntry, photo: photo)
                }
            }
            .alert("刪除日誌？", isPresented: careLogDeleteConfirmationBinding) {
                Button("取消", role: .cancel) {
                    pendingCareLogDeletion = nil
                }
                Button("刪除", role: .destructive) {
                    if let entry = pendingCareLogDeletion {
                        deleteCareLogEntry(entry)
                    }
                    pendingCareLogDeletion = nil
                }
            } message: {
                Text("刪除後無法復原。")
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
            .task {
                await careLogStore.refreshRecentEntries()
            }
            .task(id: timelineQueryID) {
                await careLogStore.loadTimeline(
                    date: selectedDate,
                    type: selectedFilter,
                    forceRefresh: true
                )
            }
            .onChange(of: selectedMode) { _, newMode in
                if newMode != .records {
                    isEditingTimeline = false
                    pendingCareLogDeletion = nil
                }
            }
    }

    @ViewBuilder
    private var careLogContent: some View {
        if usesWideLayout {
            VStack(spacing: 0) {
                headerSection
                    .frame(maxWidth: 780)

                if selectedMode == .records {
                    timelineScroll
                        .frame(maxWidth: 780)
                } else {
                    careLogTodoScroll
                        .frame(maxWidth: 780)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 0) {
                headerSection

                if selectedMode == .records {
                    timelineScroll
                } else {
                    careLogTodoScroll
                }
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var timelineScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                if careLogStore.isTimelineLoading
                    && careLogStore.timelineEntries.isEmpty {
                    ProgressView()
                        .padding(.top, 32)
                }

                if let errorMessage = careLogStore.timelineErrorMessage {
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
                            TimelineEntryRow(
                                entry: entry,
                                previewedPhotoID: previewedPhotoID,
                                onPreviewPhoto: onPreviewPhoto,
                                isEditing: userRole == .caregiver ? false : isEditingTimeline
                            ) {
                                pendingCareLogDeletion = entry
                            }
                        }
                    }
                }

                if !careLogStore.isTimelineLoading,
                   careLogStore.timelineEntries.isEmpty,
                   careLogStore.timelineErrorMessage == nil {
                    ContentUnavailableView(
                        "這天沒有照護日誌",
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .padding(.top, 24)
                }

                if careLogStore.isLoadingMoreTimeline {
                    ProgressView()
                        .padding(.vertical, 20)
                } else if careLogStore.timelineHasMore {
                    Color.clear
                        .frame(height: 1)
                        .task {
                            await careLogStore.loadMoreTimeline()
                        }
                }

                Spacer(minLength: 32)
            }
            .frame(maxWidth: usesWideLayout ? 780 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground)
        .refreshable {
            async let timelineRefresh: Void = careLogStore.loadTimeline(
                date: selectedDate,
                type: selectedFilter,
                forceRefresh: true
            )
            async let recentRefresh: Void = careLogStore.refreshRecentEntries()
            _ = await (timelineRefresh, recentRefresh)
        }
    }

    private var careLogTodoScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                careLogMedicationSection

                careLogTaskSection(title: "日常", systemImage: "checklist") {
                    VStack(spacing: 12) {
                        NavigationLink {
                            TodoView(userRole: userRole)
                        } label: {
                            HStack {
                                Text("查看待辦頁面")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(Color.brandTeal)
                            .padding(.bottom, todayTodos.isEmpty ? 0 : 4)
                        }
                        .buttonStyle(.plain)

                        if todayTodos.isEmpty {
                            emptyTaskHint("今天沒有待辦事項")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(todayTodos) { todo in
                                    TodoRow(
                                        todo: todo,
                                        allowsToggle: userRole != .caregiver
                                    ) {
                                        guard userRole != .caregiver else { return }
                                        toggleTodo(todo)
                                    }
                                    if todo.id != todayTodos.last?.id {
                                        Divider().padding(.leading, 38)
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .frame(maxWidth: usesWideLayout ? 780 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground)
        .task {
            medicationStore.load()
            todoStore.load()
        }
        .refreshable {
            medicationStore.load()
            todoStore.load()
        }
    }

    private var careLogMedicationSection: some View {
        careLogTaskSection(title: "用藥", systemImage: "pills.fill") {
            VStack(spacing: 12) {
                NavigationLink {
                    MedicationView(userRole: userRole)
                } label: {
                    HStack {
                        Text("查看用藥頁面")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color.brandTeal)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)

                MedicationTodayProgressCard(usesContainer: false) { index in
                    markDoseAsTaken(index: index)
                }
            }
        }
    }

    private func careLogTaskSection<Content: View>(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 18, weight: .bold))

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        }
    }

    private func emptyTaskHint(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.brandTeal)
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private func toggleTodo(_ todo: TodoItem) {
        if let index = todoStore.todos.firstIndex(where: { $0.id == todo.id }) {
            var updated = todoStore.todos[index]
            let wasCompleted = updated.isCompleted
            updated.isCompleted.toggle()
            withAnimation {
                todoStore.updateTodo(updated)
            }
            if !wasCompleted, updated.isCompleted {
                Task { await logTodoCompletion(updated) }
            }
        }
    }

    private func markDoseAsTaken(index: Int) {
        guard medicationStore.doses.indices.contains(index) else { return }
        let dose = medicationStore.doses[index]

        withAnimation(.easeInOut(duration: 0.3)) {
            medicationStore.markDoseTaken(index: index)
        }

        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: .medication,
            title: "\(dose.name) 已服用",
            detail: "\(dose.time) 服藥完成",
            timestamp: Date(),
            hasPhoto: false
        )
        careLogStore.entries.insert(entry, at: 0)
    }

    @MainActor
    private func logTodoCompletion(_ todo: TodoItem) async {
        let title = "完成待辦：\(todo.displayTitle(language: localeStore.code))"
        let detail = [
            "指派：\(todo.assignee.isEmpty ? "未指定" : todo.assignee)",
            "優先度：\(todo.priority.displayName)",
        ].joined(separator: "｜")
        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: .activity,
            title: title,
            detail: detail,
            timestamp: Date(),
            hasPhoto: false
        )
        do {
            try await careLogStore.addEntry(entry, photo: nil)
        } catch {
            print("[CareLogView] create completion care log failed: \(error)")
        }
    }

    // MARK: - Header with filter + calendar
    private var headerSection: some View {
        VStack(spacing: 0) {
            RootPageHeader {
                showNotifications = true
            } title: {
                Text("照護日誌")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.top, 4)

            Picker("日誌模式", selection: $selectedMode) {
                ForEach(CareLogMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, selectedMode == .records ? 10 : 12)

            if selectedMode == .records {
                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        ForEach(CareLogType.allCases, id: \.self) { type in
                            FilterChip(title: type.displayNameKey, isSelected: selectedFilter == type) {
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
            }

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
                ForEach(CalendarDisplayMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            calendarMode = mode.rawValue
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 36, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        calendarMode == mode.rawValue
                                            ? Color.brandTeal
                                            : Color.clear
                                    )
                            )
                            .foregroundStyle(
                                calendarMode == mode.rawValue
                                    ? .white
                                    : .secondary
                            )
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
        fmt.locale = localeStore.locale
        fmt.setLocalizedDateFormatFromTemplate(calendarMode == 0 ? "MMMM" : "yMMMM")
        return fmt.string(from: selectedDate)
    }

    // MARK: - Calendar body
    private var miniCalendar: some View {
        let formatter = DateFormatter()
        formatter.locale = localeStore.locale
        let weekDays = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.veryShortWeekdaySymbols
            ?? ["日", "一", "二", "三", "四", "五", "六"]

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
        let hasEntry = careLogStore.hasEntry(on: date)

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
        HStack(spacing: 10) {
            ForEach(CareLogType.allCases, id: \.self) { type in
                HStack(spacing: 4) {
                    Circle()
                        .fill(type.uiColor)
                        .frame(width: 6, height: 6)
                    Text(type.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.trailing, careLogStore.timelineEntries.isEmpty ? 16 : 48)
        .padding(.top, 0)
        .padding(.bottom, 12)
        .overlay(alignment: .trailing) {
            if userRole != .caregiver && !careLogStore.timelineEntries.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingTimeline.toggle()
                    }
                } label: {
                    Image(systemName: isEditingTimeline ? "checkmark" : "pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isEditingTimeline ? "完成編輯日誌" : "編輯日誌")
                .padding(.trailing, 16)
                .offset(y: -4)
            }
        }
    }

    private func deleteCareLogEntry(_ entry: CareLogEntry) {
        withAnimation(.easeInOut(duration: 0.2)) {
            careLogStore.deleteEntry(id: entry.id)
            if careLogStore.timelineEntries.count <= 1 {
                isEditingTimeline = false
            }
        }
    }

    private var careLogDeleteConfirmationBinding: Binding<Bool> {
        Binding {
            pendingCareLogDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingCareLogDeletion = nil
            }
        }
    }

    private enum CalendarDisplayMode: Int, CaseIterable, Identifiable {
        case week
        case month

        var id: Int { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .week: "週"
            case .month: "月"
            }
        }
    }

}

private enum CareLogMode: String, CaseIterable, Hashable, Identifiable {
    case records
    case tasks

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .records: "記錄"
        case .tasks: "待辦"
        }
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

private struct CareLogDoseRow: View {
    let dose: DoseEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dose.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(dose.isDone ? Color.brandTeal : Color(.systemGray3))

            VStack(alignment: .leading, spacing: 3) {
                Text(dose.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(dose.time)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(dose.isDone ? "已服用" : "待服用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dose.isDone ? Color.brandTeal : .secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Timeline Entry Row
struct TimelineEntryRow: View {
    let entry: CareLogEntry
    let previewedPhotoID: String?
    let onPreviewPhoto: (PhotoPreviewItem) -> Void
    let isEditing: Bool
    let onDelete: () -> Void
    @Environment(LocaleStore.self) private var localeStore

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
                HStack(alignment: .center, spacing: 10) {
                    logEntryCard
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isEditing {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("刪除日誌")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
                .animation(.easeInOut(duration: 0.2), value: isEditing)
            }
        }
    }

    private var logEntryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge
            HStack(spacing: 6) {
                Text(entry.type.displayName)
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

            Text(entry.displayTitle(language: localeStore.code))
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
                Text(entry.displayDetail(language: localeStore.code))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let photoURL = entry.photoURL {
                CachedRemotePhoto(url: photoURL) { image in
                    PreviewablePhotoSource(
                        id: "care-log-\(entry.id)",
                        image: image,
                        sourceCornerRadius: 10,
                        isPreviewed: previewedPhotoID == "care-log-\(entry.id)",
                        onPreview: onPreviewPhoto
                    ) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 112)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    .accessibilityLabel("預覽照護日誌照片")
                    .accessibilityHint("點兩下放大照片")
                } placeholder: {
                    photoPlaceholder(systemImage: "photo")
                        .frame(height: 112)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 10))
                }
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

    private func photoPlaceholder(systemImage: String) -> some View {
        ZStack {
            Color(.systemGray6)
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
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
        let bloodPressureLabel = String(
            localized: "血壓",
            locale: localeStore.locale
        )
        let bloodSugarLabel = String(
            localized: "血糖",
            locale: localeStore.locale
        )
        let parts = entry.displayDetail(language: localeStore.code)
            .components(separatedBy: "｜")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter {
                !$0.hasPrefix(bloodPressureLabel)
                    && !$0.hasPrefix(bloodSugarLabel)
            }

        // dedupe 但保留順序
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        let text = unique.joined(separator: "｜")
        return text.isEmpty ? nil : text
    }
}

private enum CareLogCreationType: String, CaseIterable, Hashable, Identifiable {
    case vital
    case medicationLog
    case meal
    case activity
    case todo
    case medicationSchedule

    var id: Self { self }

    var displayName: LocalizedStringResource {
        switch self {
        case .vital: "生命徵象"
        case .medicationLog: "服藥紀錄"
        case .meal: "飲食"
        case .activity: "活動"
        case .todo: "待辦"
        case .medicationSchedule: "用藥排程"
        }
    }

    var icon: String {
        switch self {
        case .vital: "heart.fill"
        case .medicationLog: "pills.fill"
        case .meal: "fork.knife"
        case .activity: "figure.walk"
        case .todo: "checkmark.circle.fill"
        case .medicationSchedule: "pills.circle.fill"
        }
    }

    var careLogType: CareLogType? {
        switch self {
        case .vital: .vital
        case .medicationLog: .medication
        case .meal: .meal
        case .activity: .activity
        case .todo, .medicationSchedule: nil
        }
    }
}

// MARK: - Add Care Log View
struct AddCareLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(UserStore.self) private var userStore
    @Environment(TodoStore.self) private var todoStore
    @Environment(MedicationStore.self) private var medicationStore
    let userRole: UserRole
    let onAdd: (CareLogEntry, UIImage?) async throws -> Void

    @State private var selectedCreationType: CareLogCreationType = .vital
    @State private var recordDate = Date()
    @State private var selectedPhoto: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewedPhoto: PhotoPreviewItem?
    @State private var showPhotoSourceOptions = false
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showCameraUnavailable = false
    @State private var isLoadingPhoto = false
    @State private var photoSelectionErrorMessage: String?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @FocusState private var focusedNumericField: NumericField?

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

    // todo
    @State private var todoTitle = ""
    @State private var todoSelectedMemberId: String?
    @State private var todoPriority = Priority.medium
    @State private var todoHasDueDate = true
    @State private var todoDueDate = Date()

    // medication schedule
    @State private var scheduleName = ""
    @State private var scheduleNameTranslated = ""
    @State private var scheduleDosage = ""
    @State private var scheduleFrequency = 0
    @State private var scheduleTime1 = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var scheduleTime2 = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var scheduleTime3 = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var scheduleEndDate = Date().addingTimeInterval(86400 * 30)
    @State private var scheduleNotes = ""

    private let routeLabels = ["口服", "外用", "注射"]
    private let routeDisplayLabels: [LocalizedStringResource] = [
        "口服", "外用", "注射",
    ]
    private let mealLabels = ["早餐", "午餐", "晚餐", "點心"]
    private let mealDisplayLabels: [LocalizedStringResource] = [
        "早餐", "午餐", "晚餐", "點心",
    ]
    private let appetiteLabels = ["差", "一般", "良好"]
    private let appetiteDisplayLabels: [LocalizedStringResource] = [
        "差", "一般", "良好",
    ]
    private let intensityLabels = ["輕度", "中度", "高強度"]
    private let intensityDisplayLabels: [LocalizedStringResource] = [
        "輕度", "中度", "高強度",
    ]
    private let medicationFrequencyLabels = ["每日一次", "每日兩次", "每日三次"]
    // (conditionLabels removed — vital section is now optional fields only)

    private enum NumericField: Hashable {
        case systolic
        case diastolic
        case weight
        case bloodSugar
        case temperature
        case activityDuration
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var selectedTodoAssignee: UserProfile? {
        userStore.familyMembers.first(where: { $0.id == todoSelectedMemberId })
            ?? userStore.familyMembers.first
    }

    private var selectedTodoAssigneeName: String { selectedTodoAssignee?.name ?? "" }
    private var selectedTodoAssigneeId: String? { selectedTodoAssignee?.id }

    private var medicationScheduleTimes: [String] {
        switch scheduleFrequency {
        case 0: [timeFormatter.string(from: scheduleTime1)]
        case 1: [timeFormatter.string(from: scheduleTime1), timeFormatter.string(from: scheduleTime2)]
        case 2: [timeFormatter.string(from: scheduleTime1), timeFormatter.string(from: scheduleTime2), timeFormatter.string(from: scheduleTime3)]
        default: [timeFormatter.string(from: scheduleTime1)]
        }
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private var canSaveCurrentSelection: Bool {
        switch selectedCreationType {
        case .todo:
            return !todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && selectedTodoAssigneeId != nil
        case .medicationSchedule:
            return !scheduleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !scheduleNameTranslated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .vital, .medicationLog, .meal, .activity:
            return true
        }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Form {
                    recordForm
                }
                .frame(maxWidth: usesWideLayout ? 720 : .infinity)
                .frame(maxWidth: .infinity)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("新增紀錄")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").foregroundStyle(.primary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await saveEntry() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("儲存")
                                    .fontWeight(.semibold)
                            }
                        }
                        .tint(Color.brandTeal)
                        .disabled(isSaving || isLoadingPhoto || !canSaveCurrentSelection)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        if focusedNumericField != nil {
                            Spacer()
                            KeyboardDoneButton {
                                focusedNumericField = nil
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .interactiveDismissDisabled(isSaving)
                .fullScreenCover(isPresented: $showCamera) {
                    CareLogCameraView { image in
                        selectedPhoto = image
                        selectedPhotoItem = nil
                        showCamera = false
                    } onCancel: {
                        showCamera = false
                    }
                    .ignoresSafeArea()
                }
                .photosPicker(
                    isPresented: $showPhotoLibrary,
                    selection: $selectedPhotoItem,
                    matching: .images
                )
                .onChange(of: selectedPhotoItem) { _, item in
                    guard item != nil else { return }
                    Task {
                        await loadSelectedPhoto(item)
                    }
                }
                .task {
                    await userStore.reload()
                    if todoSelectedMemberId == nil {
                        todoSelectedMemberId = userStore.familyMembers.first?.id
                    }
                }
                .alert("無法使用相機", isPresented: $showCameraUnavailable) {
                    Button("確定", role: .cancel) {}
                } message: {
                    Text("請確認裝置有相機，並在系統設定中允許 CareBridge 使用相機。")
                }
                .alert(
                    "無法載入照片",
                    isPresented: Binding(
                        get: { photoSelectionErrorMessage != nil },
                        set: {
                            if !$0 {
                                photoSelectionErrorMessage = nil
                            }
                        }
                    )
                ) {
                    Button("確定", role: .cancel) {}
                } message: {
                    Text(
                        photoSelectionErrorMessage
                            ?? "無法讀取所選照片，請重新選擇。"
                    )
                }
                .alert(
                    "儲存失敗",
                    isPresented: Binding(
                        get: { saveErrorMessage != nil },
                        set: { if !$0 { saveErrorMessage = nil } }
                    )
                ) {
                    Button("確定", role: .cancel) {}
                } message: {
                    Text(saveErrorMessage ?? "請稍後再試")
                }
            }

            if let previewedPhoto {
                PhotoPreviewOverlay(
                    item: previewedPhoto,
                    onDismiss: dismissPhotoPreview
                )
                .zIndex(10)
            }
        }
    }

    // MARK: - 紀錄 Form
    @ViewBuilder
    private var recordForm: some View {
        Section("記錄類型") {
            Picker("類型", selection: $selectedCreationType) {
                ForEach(CareLogCreationType.allCases) { t in
                    Label(t.displayName, systemImage: t.icon).tag(t)
                }
            }
        }

        switch selectedCreationType {
        case .vital, .medicationLog, .meal, .activity:
            Section("記錄時間") {
                DatePicker("時間", selection: $recordDate, displayedComponents: [.date, .hourAndMinute])
                    .tint(Color.brandTeal)
            }

            photoSection

            switch selectedCreationType {
            case .vital: vitalSection
            case .medicationLog: medicationSection
            case .meal: mealSection
            case .activity: activitySection
            case .todo, .medicationSchedule: EmptyView()
            }
        case .todo:
            todoCreationSection
        case .medicationSchedule:
            medicationScheduleSection
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let selectedPhoto {
                PreviewablePhotoSource(
                    id: "new-care-log-photo",
                    image: selectedPhoto,
                    sourceCornerRadius: 12,
                    isPreviewed: previewedPhoto != nil
                ) { item in
                    focusedNumericField = nil
                    previewedPhoto = item
                } content: {
                    Image(uiImage: selectedPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .accessibilityLabel("預覽準備上傳的照護照片")
                .accessibilityHint("點兩下放大照片")

                photoSourceButton

                Button(role: .destructive) {
                    previewedPhoto = nil
                    selectedPhotoItem = nil
                    self.selectedPhoto = nil
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .disabled(isLoadingPhoto)
            } else if isLoadingPhoto {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                photoSourceButton
            }
        } header: {
            Text("照片（選填）")
        } footer: {
            Text("照片不是必填；拍照或從相簿選擇後才會上傳。")
        }
    }

    private var photoSourceButton: some View {
        Button {
            focusedNumericField = nil
            showPhotoSourceOptions = true
        } label: {
            Label("拍照", systemImage: "camera.fill")
                .foregroundStyle(Color.brandTeal)
        }
        .confirmationDialog(
            "照片（選填）",
            isPresented: $showPhotoSourceOptions,
            titleVisibility: .hidden
        ) {
            Button("拍照") {
                openCamera()
            }
            Button("從相簿選擇") {
                showPhotoLibrary = true
            }
            Button("取消", role: .cancel) {}
        }
        .disabled(isLoadingPhoto || isSaving)
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingPhoto = true
        photoSelectionErrorMessage = nil

        defer {
            isLoadingPhoto = false
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                photoSelectionErrorMessage = String(
                    localized: "無法讀取所選照片，請重新選擇。"
                )
                return
            }
            previewedPhoto = nil
            selectedPhoto = image
        } catch is CancellationError {
            return
        } catch {
            photoSelectionErrorMessage = String(
                localized: "無法讀取所選照片，請重新選擇。"
            )
        }
    }

    private func dismissPhotoPreview() {
        previewedPhoto = nil
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        showCamera = true
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .systolic)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
            HStack {
                Text("舒張壓")
                Spacer()
                TextField("80", text: $bp_diastolic)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .diastolic)
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .weight)
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .bloodSugar)
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .temperature)
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
                    Text(routeDisplayLabels[i]).tag(i)
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
                    Text(mealDisplayLabels[i]).tag(i)
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
                    Text(appetiteDisplayLabels[i]).tag(i)
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
                    .textContentType(.oneTimeCode)
                    .focused($focusedNumericField, equals: .activityDuration)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("分鐘").foregroundStyle(.secondary)
            }
        }

        Section("強度") {
            Picker("強度", selection: $activityIntensity) {
                ForEach(0..<intensityLabels.count, id: \.self) { i in
                    Text(intensityDisplayLabels[i]).tag(i)
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

    // MARK: - 待辦 section
    @ViewBuilder
    private var todoCreationSection: some View {
        Section("待辦內容") {
            TextField("輸入待辦事項...", text: $todoTitle, axis: .vertical)
                .lineLimit(1...3)
        }

        Section("指派對象") {
            if userStore.familyMembers.isEmpty {
                Text("載入成員中...")
                    .foregroundStyle(.secondary)
            } else {
                Picker("指派給誰？", selection: $todoSelectedMemberId) {
                    ForEach(userStore.familyMembers) { member in
                        HStack(spacing: 6) {
                            Image(systemName: member.role == .caregiver ? "cross.case.fill" : "person.fill")
                                .font(.system(size: 12))
                            Text("\(member.name)（\(member.role?.displayName ?? "-")）")
                        }
                        .tag(member.id as String?)
                    }
                }
            }
        }

        Section("優先度") {
            Picker("優先度", selection: $todoPriority) {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("到期日") {
            Toggle("設定到期日", isOn: $todoHasDueDate)
                .tint(Color.brandTeal)
            if todoHasDueDate {
                DatePicker("到期日", selection: $todoDueDate, displayedComponents: .date)
                    .tint(Color.brandTeal)
            }
        }
    }

    // MARK: - 用藥排程 section
    @ViewBuilder
    private var medicationScheduleSection: some View {
        Section("藥物資訊") {
            TextField("藥品英文名稱", text: $scheduleName)
            TextField("藥品中文名稱", text: $scheduleNameTranslated)
            TextField("劑量（例：5mg）", text: $scheduleDosage)
        }

        Section("服用頻率") {
            Picker("頻率", selection: $scheduleFrequency) {
                ForEach(medicationFrequencyLabels.indices, id: \.self) { index in
                    Text(LocalizedStringKey(medicationFrequencyLabels[index])).tag(index)
                }
            }
            .pickerStyle(.segmented)
        }

        Section("服用時間") {
            DatePicker("第一次", selection: $scheduleTime1, displayedComponents: .hourAndMinute)
            if scheduleFrequency >= 1 {
                DatePicker("第二次", selection: $scheduleTime2, displayedComponents: .hourAndMinute)
            }
            if scheduleFrequency >= 2 {
                DatePicker("第三次", selection: $scheduleTime3, displayedComponents: .hourAndMinute)
            }
        }

        Section("持續到") {
            DatePicker("結束日期", selection: $scheduleEndDate, in: Date()..., displayedComponents: .date)
        }

        Section("備註") {
            TextField("注意事項（選填）", text: $scheduleNotes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    // MARK: - Save
    @MainActor
    private func saveEntry() async {
        guard !isSaving, !isLoadingPhoto else { return }
        isSaving = true
        defer { isSaving = false }

        switch selectedCreationType {
        case .todo:
            saveTodo()
            return
        case .medicationSchedule:
            saveMedicationSchedule()
            return
        case .vital, .medicationLog, .meal, .activity:
            break
        }

        let title: String
        let detail: String
        guard let type = selectedCreationType.careLogType else { return }

        switch selectedCreationType {
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
        case .medicationLog:
            title  = medName.isEmpty ? "用藥紀錄" : "\(medName) \(medDosage)"
            detail = "\(routeLabels[medRoute])｜\(medTaken ? "已服用" : "未服用")"
        case .meal:
            let trimmedMealDescription = mealDesc.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            title = trimmedMealDescription.isEmpty
                ? mealLabels[mealType]
                : trimmedMealDescription
            detail = "\(mealLabels[mealType])｜食慾：\(appetiteLabels[appetite])"
        case .activity:
            title  = activityName.isEmpty ? "活動紀錄" : activityName
            detail = "\(activityDuration.isEmpty ? "—" : activityDuration)分鐘｜\(intensityLabels[activityIntensity])"
        case .todo, .medicationSchedule:
            title  = "備註"
            detail = noteText
        }

        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: type,
            title: title,
            detail: detail,
            timestamp: recordDate,
            hasPhoto: selectedPhoto != nil,
            bloodPressureSystolic:  selectedCreationType == .vital ? Int(bp_systolic)  : nil,
            bloodPressureDiastolic: selectedCreationType == .vital ? Int(bp_diastolic) : nil,
            bloodSugar:  selectedCreationType == .vital ? Double(bloodSugar)  : nil,
            temperature: selectedCreationType == .vital ? Double(temperature) : nil,
            weight:      selectedCreationType == .vital ? Double(weight)      : nil
        )
        do {
            try await onAdd(entry, selectedPhoto)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func saveTodo() {
        let trimmedTitle = todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let assigneeId = selectedTodoAssigneeId else { return }
        let todo = TodoItem(
            id: UUID().uuidString,
            title: trimmedTitle,
            assignee: selectedTodoAssigneeName,
            priority: todoPriority,
            dueDate: todoHasDueDate ? todoDueDate : nil,
            isCompleted: false,
            assigneeId: assigneeId
        )
        todoStore.addTodo(todo)
        dismiss()
    }

    private func saveMedicationSchedule() {
        let trimmedName = scheduleName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslated = scheduleNameTranslated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty || !trimmedTranslated.isEmpty else { return }

        let frequencyEnum: String
        switch scheduleFrequency {
        case 0: frequencyEnum = "daily"
        case 1: frequencyEnum = "twice_daily"
        case 2: frequencyEnum = "thrice_daily"
        default: frequencyEnum = "daily"
        }

        let medication = Medication(
            id: UUID().uuidString,
            name: trimmedName.isEmpty ? trimmedTranslated : trimmedName,
            nameTranslated: trimmedTranslated.isEmpty ? trimmedName : trimmedTranslated,
            dosage: scheduleDosage.isEmpty ? "—" : scheduleDosage,
            frequency: frequencyEnum,
            times: medicationScheduleTimes,
            instructions: scheduleNotes,
            isActive: true,
            startDate: Date(),
            endDate: scheduleEndDate,
            reminderEnabled: true
        )
        medicationStore.addMedication(medication)
        dismiss()
    }
}

private struct CareLogCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(
            onCapture: @escaping (UIImage) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [
                UIImagePickerController.InfoKey: Any
            ]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

#Preview {
    CareLogPreviewHost()
}

private struct CareLogPreviewHost: View {
    var body: some View {
        CareLogView(
            showProfile: .constant(false),
            userRole: .family,
            previewedPhotoID: nil,
            onPreviewPhoto: { _ in }
        )
        .environment(CareLogStore())
        .environment(NotificationStore(service: MockDataService()))
        .environment(TodoStore())
        .environment(MedicationStore())
        .environment(UserStore())
    }
}

#Preview("新增") {
    AddCareLogView(userRole: .caregiver) { _, _ in }
        .environment(CareLogStore())
        .environment(TodoStore())
        .environment(MedicationStore())
        .environment(UserStore())
}
