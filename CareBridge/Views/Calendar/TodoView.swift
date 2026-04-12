import SwiftUI

struct TodoView: View {
    @Environment(TodoStore.self) private var todoStore
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(CalendarStore.self) private var calendarStore
    @State private var showAddTodo = false
    @State private var filter = 0 // 0=全部, 1=待處理, 2=已完成

    var filteredTodos: [TodoItem] {
        switch filter {
        case 1: return todoStore.todos.filter { !$0.isCompleted }
        case 2: return todoStore.todos.filter { $0.isCompleted }
        default: return todoStore.todos
        }
    }

    var pendingCount: Int { todoStore.todos.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Filter
            Picker("篩選", selection: $filter) {
                Text("全部").tag(0)
                Text("待處理").tag(1)
                Text("已完成").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if pendingCount > 0 && filter != 2 {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                    Text("共 \(pendingCount) 項待處理")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            List {
                ForEach(filteredTodos) { todo in
                    TodoRow(todo: todo) {
                        toggleTodo(todo)
                    }
                    .listRowBackground(Color.white)
                }
                .onDelete { indexSet in
                    deleteTodo(at: indexSet)
                }
            }
            .listStyle(.plain)
            .background(Color.brandBackground)
        }
        .background(Color.brandBackground)
        .navigationTitle("代辦事項")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddTodo = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.brandTeal)
                        .font(.system(size: 22))
                }
            }
        }
        .sheet(isPresented: $showAddTodo) {
            AddTodoView { newTodo in
                todoStore.addTodo(newTodo)
                // Sync to shared calendar
                let calEvent = CalendarEvent(
                    id: UUID().uuidString,
                    title: "📋 \(newTodo.title)",
                    date: newTodo.dueDate ?? Date(),
                    location: "負責人：\(newTodo.assignee)",
                    type: "待辦"
                )
                calendarStore.addEvent(calEvent)
            }
        }
        .task { todoStore.load() }
    }

    private func toggleTodo(_ todo: TodoItem) {
        if let index = todoStore.todos.firstIndex(where: { $0.id == todo.id }) {
            let wasCompleted = todoStore.todos[index].isCompleted
            var updated = todoStore.todos[index]
            updated.isCompleted.toggle()
            withAnimation {
                todoStore.updateTodo(updated)
            }

            // Sync completion to care log + calendar
            if !wasCompleted {
                // Add care log entry
                let logEntry = CareLogEntry(
                    id: UUID().uuidString,
                    type: .note,
                    title: "待辦完成：\(todo.title)",
                    detail: "負責人：\(todo.assignee)｜優先度：\(todo.priority.displayName)",
                    timestamp: Date(),
                    hasPhoto: false
                )
                careLogStore.addEntry(logEntry)

                // Add calendar event
                let calEvent = CalendarEvent(
                    id: UUID().uuidString,
                    title: "✅ \(todo.title)",
                    date: Date(),
                    location: nil,
                    type: "完成"
                )
                calendarStore.addEvent(calEvent)
            }
        }
    }

    private func deleteTodo(at indexSet: IndexSet) {
        let toDelete = indexSet.map { filteredTodos[$0] }
        withAnimation {
            todoStore.todos.removeAll { todo in toDelete.contains { $0.id == todo.id } }
        }
    }
}

// MARK: - Todo Row
struct TodoRow: View {
    let todo: TodoItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(todo.isCompleted ? Color.brandTeal : Color(.systemGray3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Assignee
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(todo.assignee)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    // Due date
                    if let dueDate = todo.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12))
                                .foregroundStyle(dueDate < Date() && !todo.isCompleted ? .red : .secondary)
                        }
                    }
                }
            }

            Spacer()

            // Priority badge
            if !todo.isCompleted {
                Text(todo.priority.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(todo.priority.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(todo.priority.color.opacity(0.12))
                    )
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Add Todo View
struct AddTodoView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (TodoItem) -> Void

    @State private var title = ""
    @State private var assignee = ""
    @State private var priority = Priority.medium
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400)

    var body: some View {
        NavigationStack {
            Form {
                Section("任務名稱") {
                    TextField("輸入代辦事項...", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("指派對象") {
                    TextField("指派給誰？", text: $assignee)
                }

                Section("優先度") {
                    Picker("優先度", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            HStack {
                                Circle().fill(p.color).frame(width: 8, height: 8)
                                Text(p.displayName)
                            }
                            .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("到期日") {
                    Toggle("設定到期日", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("到期日", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle("新增代辦")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        let todo = TodoItem(
                            id: UUID().uuidString,
                            title: title.isEmpty ? "新代辦事項" : title,
                            assignee: assignee.isEmpty ? "未指派" : assignee,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
                            isCompleted: false
                        )
                        onAdd(todo)
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
        TodoView()
    }
    .environment(TodoStore())
    .environment(CareLogStore())
    .environment(CalendarStore())
}
