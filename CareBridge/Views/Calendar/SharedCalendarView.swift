import SwiftUI

struct SharedCalendarView: View {
    @Environment(CalendarStore.self) private var calendarStore
    @State private var selectedDate = Date()
    @State private var showAddEvent = false
    @State private var viewMode = 0 // 0=月, 1=日

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        f.locale = Locale(identifier: "zh-TW")
        return f
    }()

    private var daysInMonth: [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    private var selectedDayEvents: [CalendarEvent] {
        calendarStore.events.filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Month header
                HStack {
                    Button {
                        selectedDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.brandTeal)
                    }
                    Spacer()
                    Text(monthFormatter.string(from: selectedDate))
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button {
                        selectedDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.brandTeal)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Weekday headers
                HStack(spacing: 0) {
                    ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)

                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                        if let date = date {
                            DayCell(
                                date: date,
                                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                isToday: calendar.isDateInToday(date),
                                hasEvent: calendarStore.events.contains { calendar.isDate($0.date, inSameDayAs: date) }
                            ) {
                                selectedDate = date
                            }
                        } else {
                            Color.clear.frame(height: 40)
                        }
                    }
                }
                .padding(.horizontal, 12)

                Divider()

                // Selected day events
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selectedDate.formatted(date: .complete, time: .omitted))
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button {
                            showAddEvent = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.brandTeal)
                                .font(.system(size: 22))
                        }
                    }
                    .padding(.horizontal, 16)

                    if selectedDayEvents.isEmpty {
                        Text("今日無行程")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    } else {
                        // Ensure chronological order for the day's events
                        ForEach(selectedDayEvents.sorted { $0.date < $1.date }) { event in
                            EventRow(event: event)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("共享行事曆")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddEvent) {
            Text("新增行程")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.brandBackground)
        }
        .task { calendarStore.load() }
    }
}

// MARK: - Day Cell
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEvent: Bool
    let action: () -> Void
    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.brandTeal)
                            .frame(width: 34, height: 34)
                    } else if isToday {
                        Circle()
                            .stroke(Color.brandTeal, lineWidth: 2)
                            .frame(width: 34, height: 34)
                    }
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? .white : isToday ? Color.brandTeal : .primary)
                }
                if hasEvent {
                    Circle()
                        .fill(isSelected ? .white : Color.brandTeal)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(event.typeColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: event.typeIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(event.typeColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .medium))
                if let location = event.location {
                    Text(location)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(event.typeColor)
                Text(event.date.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SharedCalendarView()
    }
    .environment(CalendarStore())
}
