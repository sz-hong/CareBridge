import SwiftUI

struct MedicationView: View {
    var userRole: UserRole = .family
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(MedicationStore.self) private var medStore
    @Environment(CareLogStore.self) private var careLogStore
    @State private var editingMedication: Medication?
    @State private var pendingMedicationDeletion: Medication?

    /// Hide meds whose endDate has already passed — they should silently
    /// disappear from the active list once their treatment course is over.
    private var activeMedications: [Medication] {
        let today = Calendar.current.startOfDay(for: Date())
        return medStore.medications.filter { med in
            guard let end = med.endDate else { return true }   // no end → indefinite
            return Calendar.current.startOfDay(for: end) >= today
        }
    }

    var body: some View {
        ScrollView {
            medicationContent
        }
        .background(Color.brandBackground)
        .navigationTitle("用藥管理")
        .navigationBarTitleDisplayMode(.large)
        .task { medStore.load() }
        .alert("刪除用藥？", isPresented: medicationDeleteConfirmationBinding) {
            Button("取消", role: .cancel) {
                pendingMedicationDeletion = nil
            }
            Button("刪除", role: .destructive) {
                if let medication = pendingMedicationDeletion {
                    deleteMedication(medication)
                }
                pendingMedicationDeletion = nil
            }
        } message: {
            Text("刪除後會同步移除今日服藥進度。")
        }
        .sheet(item: $editingMedication) { medication in
            EditMedicationView(medication: medication)
        }
    }

    @ViewBuilder
    private var medicationContent: some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: 20) {
                todaySummaryCard
                    .frame(maxWidth: 420)
                medicationListCard
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                todaySummaryCard
                    .padding(.horizontal, 16)

                medicationListCard
                    .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var medicationListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("目前用藥清單")
                .font(.system(size: 17, weight: .bold))

            if activeMedications.isEmpty {
                Text("目前沒有用藥項目")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(activeMedications) { med in
                        if userRole == .caregiver {
                            MedicationRow(medication: med)
                        } else {
                            SwipeToDeleteMedicationRow(
                                medication: med,
                                onEdit: { editingMedication = med },
                                onDelete: { pendingMedicationDeletion = med }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Today's Summary
    private var todaySummaryCard: some View {
        MedicationTodayProgressCard { index in
            markDoseAsTaken(index: index)
        }
    }

    private func markDoseAsTaken(index: Int) {
        guard medStore.doses.indices.contains(index) else { return }
        let dose = medStore.doses[index]

        withAnimation(.easeInOut(duration: 0.3)) {
            medStore.markDoseTaken(index: index)
        }

        // Backend's `confirmMedication` endpoint already creates a CareLog entry
        // (see medication/views.py confirm action). Insert locally for instant UI
        // feedback without re-posting and creating a duplicate row.
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

    private func deleteMedication(_ medication: Medication) {
        withAnimation(.easeInOut(duration: 0.2)) {
            medStore.deleteMedication(id: medication.id)
        }
    }

    private var medicationDeleteConfirmationBinding: Binding<Bool> {
        Binding {
            pendingMedicationDeletion != nil
        } set: { isPresented in
            if !isPresented {
                pendingMedicationDeletion = nil
            }
        }
    }
}

struct MedicationTodayProgressCard: View {
    var usesContainer = true
    let onMarkDoseTaken: (Int) -> Void
    @Environment(MedicationStore.self) private var medStore

    var body: some View {
        cardContent
            .padding(usesContainer ? 16 : 0)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(usesContainer ? Color.white : Color.clear)
            )
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日服藥進度")
                .font(.system(size: 17, weight: .bold))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(medStore.takenCount) / \(medStore.totalCount)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.brandTeal)
                    Text("已服用")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: medStore.progress)
                        .stroke(Color.brandTeal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: medStore.progress)
                }
                .frame(width: 64, height: 64)
            }

            // Timeline
            if medStore.doses.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.brandTeal)
                    Text("今天沒有待服用藥物")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(medStore.doses.enumerated()), id: \.element.id) { index, dose in
                        doseRow(index: index, dose: dose)
                        if index < medStore.doses.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
            }
        }
    }

    private func doseRow(index: Int, dose: DoseEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(dose.isDone ? Color.brandTeal : Color(.systemGray4))
                    .frame(width: 28, height: 28)
                Image(systemName: dose.isDone ? "checkmark" : "clock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(dose.time)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text(dose.name)
                .font(.system(size: 14))
                .foregroundStyle(dose.isDone ? .secondary : .primary)
            Spacer()
            if dose.isDone {
                Text("已服用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button {
                    onMarkDoseTaken(index)
                } label: {
                    Text("服用")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.brandTeal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Medication Row
struct SwipeToDeleteMedicationRow: View {
    let medication: Medication
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0

    private let deleteWidth: CGFloat = 82

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { offset = 0 }
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("刪除")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: deleteWidth)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 12).fill(.red))
            }
            .buttonStyle(.plain)

            MedicationRow(medication: medication, onEdit: {
                if offset < 0 {
                    withAnimation(.easeInOut(duration: 0.2)) { offset = 0 }
                } else {
                    onEdit()
                }
            })
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -deleteWidth)
                        } else if offset < 0 {
                            offset = min(0, -deleteWidth + value.translation.width)
                        }
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            offset = value.translation.width < -(deleteWidth / 2) ? -deleteWidth : 0
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.2), value: offset)
        }
        .clipped()
    }
}

struct MedicationRow: View {
    let medication: Medication
    var onEdit: (() -> Void)? = nil
    @State private var isExpanded = false
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if let onEdit {
                        onEdit()
                    } else {
                        toggleExpanded()
                    }
                } label: {
                    medicationSummary
                }
                .buttonStyle(.plain)

                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    if !medication.instructions.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 14))
                            Text(medication.displayInstructions(language: localeStore.code))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let endDate = medication.endDate {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(Color.brandTeal)
                                .font(.system(size: 14))
                            Text("用藥結束日：\(endDate.formatted(date: .long, time: .omitted))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    private var medicationSummary: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.brandTealLight)
                    .frame(width: 44, height: 44)
                Image(systemName: "pills.fill")
                    .foregroundStyle(Color.brandTeal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(medication.name)（\(medication.nameTranslated)）")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text("\(medication.dosage) · \(frequencyLabel)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    ForEach(medication.times, id: \.self) { time in
                        Text(time)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.brandTealLight))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var frequencyLabel: String {
        switch medication.frequency {
        case "daily": return localizedFrequencyLabel("每日一次")
        case "twice_daily": return localizedFrequencyLabel("每日兩次")
        case "thrice_daily": return localizedFrequencyLabel("每日三次")
        case "weekly": return localizedFrequencyLabel("每週一次")
        case "as_needed": return localizedFrequencyLabel("需要時服用")
        default: return medication.frequency
        }
    }

    private func toggleExpanded() {
        withAnimation(.spring(duration: 0.3)) {
            isExpanded.toggle()
        }
    }

    private func localizedFrequencyLabel(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: localeStore.locale)
    }
}

// MARK: - Add Medication View
struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onAdd: (Medication) -> Void

    @State private var name = ""
    @State private var nameTranslated = ""
    @State private var dosage = ""
    @State private var frequency = 0
    @State private var time1 = dateFrom(hour: 8, minute: 0)
    @State private var time2 = dateFrom(hour: 14, minute: 0)
    @State private var time3 = dateFrom(hour: 20, minute: 0)
    @State private var endDate = Date().addingTimeInterval(86400 * 30)
    @State private var notes = ""

    private let frequencyLabels = ["每日一次", "每日兩次", "每日三次"]
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeStrings: [String] {
        switch frequency {
        case 0: return [timeFmt.string(from: time1)]
        case 1: return [timeFmt.string(from: time1), timeFmt.string(from: time2)]
        case 2: return [timeFmt.string(from: time1), timeFmt.string(from: time2), timeFmt.string(from: time3)]
        default: return [timeFmt.string(from: time1)]
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("藥物資訊") {
                    TextField("藥品英文名稱", text: $name)
                    TextField("藥品中文名稱", text: $nameTranslated)
                    TextField("劑量（例：5mg）", text: $dosage)
                }

                Section("服用頻率") {
                    Picker("頻率", selection: $frequency) {
                        ForEach(0..<frequencyLabels.count, id: \.self) { i in
                            Text(LocalizedStringKey(frequencyLabels[i])).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("服用時間") {
                    DatePicker("第一次", selection: $time1, displayedComponents: .hourAndMinute)
                    if frequency >= 1 {
                        DatePicker("第二次", selection: $time2, displayedComponents: .hourAndMinute)
                    }
                    if frequency >= 2 {
                        DatePicker("第三次", selection: $time3, displayedComponents: .hourAndMinute)
                    }
                }

                Section("持續到") {
                    DatePicker("結束日期", selection: $endDate, in: Date()..., displayedComponents: .date)
                }

                Section("備註") {
                    TextField("注意事項（選填）", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("新增藥物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") {
                        saveMedication()
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(name.isEmpty && nameTranslated.isEmpty)
                }
            }
        }
    }

    private func saveMedication() {
        let times = timeStrings
        let frequencyEnum: String
        switch frequency {
        case 0: frequencyEnum = "daily"
        case 1: frequencyEnum = "twice_daily"
        case 2: frequencyEnum = "thrice_daily"
        default: frequencyEnum = "daily"
        }

        let med = Medication(
            id: UUID().uuidString,
            name: name.isEmpty ? nameTranslated : name,
            nameTranslated: nameTranslated.isEmpty ? name : nameTranslated,
            dosage: dosage.isEmpty ? "—" : dosage,
            frequency: frequencyEnum,
            times: times,
            instructions: notes,
            isActive: true,
            startDate: Date(),
            endDate: endDate,
            reminderEnabled: true
        )
        // Medications no longer fan out to the shared calendar — endDate is
        // shown in the medication accordion, and the active list filters out
        // expired ones automatically (see activeMedications).
        onAdd(med)
        dismiss()
    }

    private static func dateFrom(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}


// MARK: - Edit Medication View
struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(MedicationStore.self) private var medStore

    let medication: Medication
    @State private var name: String
    @State private var nameTranslated: String
    @State private var dosage: String
    @State private var frequency: Int
    @State private var time1: Date
    @State private var time2: Date
    @State private var time3: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var notes: String
    @State private var reminderEnabled: Bool

    private let frequencyLabels = ["每日一次", "每日兩次", "每日三次", "每週一次", "需要時服用"]
    private let frequencyValues = ["daily", "twice_daily", "thrice_daily", "weekly", "as_needed"]
    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(medication: Medication) {
        self.medication = medication
        let firstTime = Self.timeString(at: 0, from: medication.times, fallback: "08:00")
        let secondTime = Self.timeString(at: 1, from: medication.times, fallback: "14:00")
        let thirdTime = Self.timeString(at: 2, from: medication.times, fallback: "20:00")
        _name = State(initialValue: medication.name)
        _nameTranslated = State(initialValue: medication.nameTranslated)
        _dosage = State(initialValue: medication.dosage)
        _frequency = State(initialValue: Self.frequencyIndex(for: medication.frequency))
        _time1 = State(initialValue: Self.date(from: firstTime, fallbackHour: 8))
        _time2 = State(initialValue: Self.date(from: secondTime, fallbackHour: 14))
        _time3 = State(initialValue: Self.date(from: thirdTime, fallbackHour: 20))
        _hasEndDate = State(initialValue: medication.endDate != nil)
        _endDate = State(initialValue: medication.endDate ?? Date().addingTimeInterval(86400 * 30))
        _notes = State(initialValue: medication.instructions)
        _reminderEnabled = State(initialValue: medication.reminderEnabled)
    }

    private var timeStrings: [String] {
        switch frequencyValues[frequency] {
        case "twice_daily": return [timeFmt.string(from: time1), timeFmt.string(from: time2)]
        case "thrice_daily": return [timeFmt.string(from: time1), timeFmt.string(from: time2), timeFmt.string(from: time3)]
        default: return [timeFmt.string(from: time1)]
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !nameTranslated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("藥品資料") {
                    TextField("藥品名稱", text: $name)
                    TextField("中文或顯示名稱", text: $nameTranslated)
                    TextField("劑量（例：5mg）", text: $dosage)
                }

                Section("服用頻率") {
                    Picker("頻率", selection: $frequency) {
                        ForEach(frequencyLabels.indices, id: \.self) { index in
                            Text(LocalizedStringKey(frequencyLabels[index])).tag(index)
                        }
                    }
                }

                Section("服用時間") {
                    DatePicker("第一次", selection: $time1, displayedComponents: .hourAndMinute)
                    if frequencyValues[frequency] == "twice_daily" || frequencyValues[frequency] == "thrice_daily" {
                        DatePicker("第二次", selection: $time2, displayedComponents: .hourAndMinute)
                    }
                    if frequencyValues[frequency] == "thrice_daily" {
                        DatePicker("第三次", selection: $time3, displayedComponents: .hourAndMinute)
                    }
                }

                Section("療程設定") {
                    Toggle("設定結束日", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("結束日", selection: $endDate, displayedComponents: .date)
                    }
                    Toggle("啟用提醒", isOn: $reminderEnabled)
                }

                Section("備註") {
                    TextField("例如飯後使用、注意事項", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("編輯用藥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { saveMedication() }
                        .bold()
                        .foregroundStyle(canSave ? Color.brandTeal : Color.secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveMedication() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslatedName = nameTranslated.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDosage = dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? trimmedTranslatedName : trimmedName
        let displayTranslatedName = trimmedTranslatedName.isEmpty ? displayName : trimmedTranslatedName
        let updated = Medication(
            id: medication.id,
            name: displayName,
            nameTranslated: displayTranslatedName,
            dosage: trimmedDosage.isEmpty ? medication.dosage : trimmedDosage,
            frequency: frequencyValues[frequency],
            times: timeStrings,
            instructions: trimmedNotes,
            isActive: medication.isActive,
            startDate: medication.startDate,
            endDate: hasEndDate ? endDate : nil,
            reminderEnabled: reminderEnabled,
            instructionsTranslations: trimmedNotes == medication.instructions ? medication.instructionsTranslations : nil
        )
        medStore.updateMedication(updated)
        dismiss()
    }

    private static func frequencyIndex(for value: String) -> Int {
        switch value {
        case "twice_daily": return 1
        case "thrice_daily": return 2
        case "weekly": return 3
        case "as_needed": return 4
        default: return 0
        }
    }

    private static func timeString(at index: Int, from times: [String], fallback: String) -> String {
        times.indices.contains(index) ? times[index] : fallback
    }

    private static func date(from time: String, fallbackHour: Int) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let hour = parts.indices.contains(0) ? parts[0] : fallbackHour
        let minute = parts.indices.contains(1) ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}

#Preview {
    NavigationStack {
        MedicationView(userRole: .caregiver)
            .environment(MedicationStore())
            .environment(CareLogStore())
    }
}
