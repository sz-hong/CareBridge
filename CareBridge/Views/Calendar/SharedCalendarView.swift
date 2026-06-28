import SwiftUI

struct SharedCalendarView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.floatingActionBottomPadding) private var floatingActionBottomPadding
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(TodoStore.self) private var todoStore
    @Environment(LocaleStore.self) private var localeStore
    @State private var selectedDate = Date()
    @State private var showAddSheet = false
    @State private var addType: AddType = .event

    private enum AddType { case event, todo }

    private let calendar = Calendar.current
    private var monthFormatter: DateFormatter {
        LocalizedFormatters.monthYear(for: localeStore.locale)
    }

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

    private var selectedDayTodos: [TodoItem] {
        todoStore.todos.filter { todo in
            guard let due = todo.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: selectedDate)
        }
    }

    /// True if the given date has any event or todo — used for the calendar dot.
    private func hasAnythingOn(_ date: Date) -> Bool {
        calendarStore.events.contains { calendar.isDate($0.date, inSameDayAs: date) }
            || todoStore.todos.contains { todo in
                guard let due = todo.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: date)
            }
    }

    var body: some View {
        ScrollView {
            calendarContent
        }
        .background(Color.brandBackground)
        .navigationTitle("共享行事曆")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottomTrailing) {
            Menu {
                Button {
                    addType = .event
                    showAddSheet = true
                } label: {
                    Label("新增行程", systemImage: "calendar")
                }
                Button {
                    addType = .todo
                    showAddSheet = true
                } label: {
                    Label("新增待辦事項", systemImage: "checkmark.circle")
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.brandTeal)
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.trailing, usesWideLayout ? 32 : 24)
            .padding(.bottom, floatingActionBottomPadding)
        }
        .sheet(isPresented: $showAddSheet) {
            switch addType {
            case .event:
                AddEventView(defaultDate: selectedDate) { newEvent in
                    calendarStore.addEvent(newEvent)
                }
            case .todo:
                AddTodoView { newTodo in
                    todoStore.addTodo(newTodo)
                }
            }
        }
        .task {
            calendarStore.load()
            todoStore.load()
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: 20) {
                calendarCard
                    .frame(maxWidth: 640)
                selectedDayAgendaCard
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                calendarCore

                Divider()

                selectedDayAgendaCard
                    .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var calendarCard: some View {
        calendarCore
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
    }

    private var calendarCore: some View {
        VStack(spacing: 16) {
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
            .padding(.top, usesWideLayout ? 0 : 8)

            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: usesWideLayout ? 12 : 8) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasEvent: hasAnythingOn(date)
                        ) {
                            selectedDate = date
                        }
                    } else {
                        Color.clear.frame(height: usesWideLayout ? 50 : 40)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var selectedDayAgendaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.formatted(date: .complete, time: .omitted))
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)

            if selectedDayEvents.isEmpty && selectedDayTodos.isEmpty {
                Text("今日無行程")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ForEach(selectedDayEvents.sorted { $0.date < $1.date }) { event in
                    EventRow(event: event)
                        .padding(.horizontal, 16)
                }
                ForEach(selectedDayTodos) { todo in
                    CalendarTodoRow(todo: todo) {
                        toggleTodo(todo)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private func toggleTodo(_ todo: TodoItem) {
        if let index = todoStore.todos.firstIndex(where: { $0.id == todo.id }) {
            var updated = todoStore.todos[index]
            updated.isCompleted.toggle()
            withAnimation { todoStore.updateTodo(updated) }
        }
    }
}

// MARK: - Calendar Todo Row (compact toggleable row for the day list)
struct CalendarTodoRow: View {
    let todo: TodoItem
    let onToggle: () -> Void
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(todo.isCompleted ? Color.brandTeal : Color(.systemGray3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.displayTitle(language: localeStore.code))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(todo.assignee)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !todo.isCompleted {
                Text(todo.priority.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(todo.priority.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(todo.priority.color.opacity(0.12)))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Event View (lightweight inline form)
struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let defaultDate: Date
    let onAdd: (CalendarEvent) -> Void

    @State private var title = ""
    @State private var date: Date
    @State private var location = ""
    @State private var type = "其他"
    private let types = ["回診", "復健", "個人", "其他"]

    init(defaultDate: Date, onAdd: @escaping (CalendarEvent) -> Void) {
        self.defaultDate = defaultDate
        self.onAdd = onAdd
        _date = State(initialValue: defaultDate)
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("行程資訊") {
                    TextField("標題", text: $title)
                    DatePicker("時間", selection: $date)
                    TextField("地點（選填）", text: $location)
                }
                Section("類型") {
                    Picker("類型", selection: $type) {
                        ForEach(types, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("新增行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        let event = CalendarEvent(
                            id: UUID().uuidString,
                            title: title.isEmpty ? "未命名行程" : title,
                            date: date,
                            location: location.isEmpty ? nil : location,
                            type: type
                        )
                        onAdd(event)
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(title.isEmpty)
                }
            }
        }
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
            // Always reserve the dot row (clear when no event) so day numbers
            // stay vertically aligned across the whole week instead of getting
            // pushed up only on cells that have events.
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
                Circle()
                    .fill(hasEvent ? (isSelected ? .white : Color.brandTeal) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event Row
struct EventRow: View {
    @Environment(LocaleStore.self) private var localeStore
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
                Text(event.displayTitle(language: localeStore.code))
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
