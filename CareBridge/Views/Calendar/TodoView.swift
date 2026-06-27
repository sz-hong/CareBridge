import SwiftUI

struct TodoView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(TodoStore.self) private var todoStore
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(LocaleStore.self) private var localeStore
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
            .padding(.horizontal, usesWideLayout ? 32 : 16)
            .padding(.vertical, 12)
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)

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
                .padding(.horizontal, usesWideLayout ? 32 : 16)
                .padding(.bottom, 8)
                .frame(maxWidth: usesWideLayout ? 900 : .infinity)
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
            .frame(maxWidth: usesWideLayout ? 900 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground)
        .navigationTitle("代辦事項")
        .navigationBarTitleDisplayMode(.large)
        .task { todoStore.load() }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
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
            print("[TodoView] create completion care log failed: \(error)")
        }
    }

    private func deleteTodo(at indexSet: IndexSet) {
        let toDelete = indexSet.map { filteredTodos[$0] }
        withAnimation {
            toDelete.forEach { todoStore.deleteTodo($0) }
        }
    }
}

// MARK: - Todo Row
struct TodoRow: View {
    let todo: TodoItem
    let onToggle: () -> Void
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(todo.isCompleted ? Color.brandTeal : Color(.systemGray3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.displayTitle(language: localeStore.code))
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
    @Environment(UserStore.self) private var userStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onAdd: (TodoItem) -> Void

    @State private var title = ""
    @State private var selectedMemberId: String? = nil
    @State private var priority = Priority.medium
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400)

    private var selectedAssignee: UserProfile? {
        userStore.familyMembers.first(where: { $0.id == selectedMemberId })
            ?? userStore.familyMembers.first
    }

    private var selectedAssigneeName: String { selectedAssignee?.name ?? "" }
    private var selectedAssigneeId: String? { selectedAssignee?.id }
    private var canSave: Bool { !title.isEmpty && selectedAssigneeId != nil }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任務名稱") {
                    TextField("輸入代辦事項...", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("指派對象") {
                    if userStore.familyMembers.isEmpty {
                        Text("載入成員中...").foregroundStyle(.secondary)
                    } else {
                        Picker("指派給誰？", selection: $selectedMemberId) {
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
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
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
                            assignee: selectedAssigneeName,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
                            isCompleted: false,
                            assigneeId: selectedAssigneeId
                        )
                        onAdd(todo)
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(canSave ? Color.brandTeal : Color.secondary)
                    .disabled(!canSave)
                }
            }
            .task {
                await userStore.reload()
                if selectedMemberId == nil {
                    selectedMemberId = userStore.familyMembers.first?.id
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
