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
    case calendar, todos, medication, health
}

// MARK: - HomeView
struct HomeView: View {
    @Binding var showProfile: Bool
    @Binding var isInHomeDetail: Bool
    let userRole: UserRole
    @Environment(UserStore.self) private var userStore
    @Environment(MedicationStore.self) private var medicationStore
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(TodoStore.self) private var todoStore
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(\.dataService) private var service
    @State private var health: HealthData = .sample
    @State private var weeklySteps: [Int] = HealthData.weeklySteps
    @State private var showNotifications = false
    @State private var navPath = NavigationPath()
    @State private var liveSocket = HealthLiveSocket()
    private let weekDays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    /// 今天在 Mon-Sun 陣列中的 index（Mon=0, Sun=6）
    private var todayWeekdayIndex: Int {
        // Calendar.weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let weekday = Calendar.current.component(.weekday, from: Date())
        return (weekday + 5) % 7
    }

    /// 下一劑尚未服用的藥物時間字串
    private var nextDoseDescription: String {
        let cal = Calendar.current
        let now = Date()
        let curMins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let upcoming = medicationStore.doses.first {
            !$0.isDone && timeStringToMinutes($0.time) > curMins
        }
        guard let d = upcoming else {
            return medicationStore.doses.isEmpty ? "暫無藥物" : "今日完成"
        }
        return "Next: \(d.time)"
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
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 20) {
                    // Greeting
                    greetingSection

                    // Activity Trend Card
                    activityTrendCard

                    // Today's Tasks
                    todayTasksCard

                    // Heart Rate Card
                    heartRateCard

                    // Blood Oxygen Card
                    bloodOxygenCard

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
            .navigationDestination(for: HomeDestination.self) { dest in
                switch dest {
                case .calendar:   SharedCalendarView()
                case .todos:      TodoView()
                case .medication: MedicationView(userRole: userRole)
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
                careLogStore.load()
                todoStore.load()
                calendarStore.load()
                async let h = service.fetchHealthData(elderId: "")
                async let s = service.fetchWeeklySteps(elderId: "")
                health      = (try? await h) ?? .sample
                weeklySteps = (try? await s) ?? HealthData.weeklySteps

                // Live updates from any family member's HealthKit upload —
                // mirror the heart rate / SpO2 values into the home cards
                // so they refresh in real time as the watch streams data.
                liveSocket.onUpdate = { update in
                    applyLiveUpdate(update)
                }
                liveSocket.connect()
            }
            .onDisappear { liveSocket.disconnect() }
        }
    }

    private func applyLiveUpdate(_ update: HealthLiveUpdate) {
        for point in update.points {
            switch point.type {
            case "heart_rate":
                health.heartRate = Int(point.value)
                health.timestamp = point.recordedAt
            case "blood_oxygen":
                health.bloodOxygen = point.value
                health.timestamp = point.recordedAt
            default: break
            }
        }
    }

    // MARK: - Greeting
    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
                Text(userStore.currentUser?.name ?? "")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default: return "Good evening,"
        }
    }


    // MARK: - Activity Trend Card
    private var activityTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity Trend")
                        .font(.system(size: 17, weight: .bold))
                    Text("Movement & Steps last 7 days")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 0) {
                    Text("Week")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandTealLight))
                        .foregroundStyle(Color.brandTeal)
                    Text("Month")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
            }

            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeklySteps.enumerated()), id: \.offset) { index, steps in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == todayWeekdayIndex ? Color.brandTeal : Color.brandTealLight)
                            .frame(height: CGFloat(steps) / 35)
                        Text(weekDays[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
            .padding(.vertical, 4)

            Divider()

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("12% more active than last week")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink(value: HomeDestination.health) {
                    Text("FULL\nREPORT")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.brandTeal)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private var todayTodos: [TodoItem] {
        todoStore.todos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return Calendar.current.isDateInToday(due) && !todo.isCompleted
        }
    }

    private var todayEvents: [CalendarEvent] {
        calendarStore.events
            .filter { Calendar.current.isDateInToday($0.date) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Today's Tasks
    private var todayTasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日處理事項")
                .font(.system(size: 17, weight: .bold))

            // Today's events (always visible — empty state when no events)
            NavigationLink(value: HomeDestination.calendar) {
                taskRow(
                    icon: "calendar",
                    title: "今日行程",
                    subtitle: todayEvents.first.map {
                        "\($0.date.formatted(date: .omitted, time: .shortened))  \($0.title)"
                    } ?? "今日無行程",
                    primaryValue: "\(todayEvents.count)",
                    secondaryValue: "項"
                )
            }
            .buttonStyle(.plain)

            // Today's todos (always visible — empty state when no todos)
            NavigationLink(value: HomeDestination.todos) {
                taskRow(
                    icon: "checkmark.circle.fill",
                    title: "今日待辦",
                    subtitle: todayTodos.first?.title ?? "今日無待辦",
                    primaryValue: "\(todayTodos.count)",
                    secondaryValue: "待完成"
                )
            }
            .buttonStyle(.plain)

            // Medication row
            NavigationLink(value: HomeDestination.medication) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandTealLight)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "pills.fill")
                                .foregroundStyle(Color.brandTeal)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Medication")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(nextDoseDescription)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(medicationStore.takenCount)/\(medicationStore.totalCount)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.brandTeal)
                        Text("DONE")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)

            // Blood pressure row
            NavigationLink(value: HomeDestination.health) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.brandTealLight)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundStyle(Color.brandTeal)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pressure")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Last check: \((latestBloodPressure?.at ?? health.timestamp).formatted(.dateTime.hour().minute()))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(latestBloodPressure.map { "\($0.systolic)/\($0.diastolic)" } ?? "--/--")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("NORMAL")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    /// Shared row layout used by 今日行程 / 今日待辦 — matches the Medication
    /// row's brandTeal palette so the four entries form a consistent column.
    private func taskRow(
        icon: String,
        title: String,
        subtitle: String,
        primaryValue: String,
        secondaryValue: String
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
                Text(subtitle)
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
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
    }

    // MARK: - Heart Rate Card
    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("HEART RATE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("STABLE")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(health.heartRate)")
                    .font(.system(size: 52, weight: .bold))
                Text("bpm")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Spacer()
                // Mini pulse graphic
                HStack(alignment: .center, spacing: 2) {
                    ForEach([0.3, 0.6, 1.0, 0.7, 0.5, 0.8, 0.4], id: \.self) { h in
                        Capsule()
                            .fill(Color(red: 1.0, green: 0.6, blue: 0.6))
                            .frame(width: 4, height: 40 * h)
                    }
                }
                .frame(height: 40)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Blood Oxygen Card
    private var bloodOxygenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wind")
                    .foregroundStyle(Color.brandTeal)
                Text("BLOOD OXYGEN")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.brandTeal)
                        .frame(width: 6, height: 6)
                    Text("OPTIMAL")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.brandTeal)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(Int(health.bloodOxygen))")
                    .font(.system(size: 52, weight: .bold))
                Text("% SpO2")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
                Spacer()
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}

#Preview {
    let svc = MockDataService()
    HomeView(showProfile: .constant(false), isInHomeDetail: .constant(false), userRole: .family)
        .environment(MedicationStore(service: svc))
        .environment(CareLogStore(service: svc))
        .environment(CalendarStore(service: svc))
        .environment(TodoStore(service: svc))
        .environment(UserStore(service: svc))
}
