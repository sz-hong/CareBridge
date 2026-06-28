import SwiftUI

struct MedicationView: View {
    var userRole: UserRole = .family
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(MedicationStore.self) private var medStore
    @Environment(CareLogStore.self) private var careLogStore
    @State private var isEditingMedicationList = false
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
            HStack {
                Text("目前用藥清單")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                if !activeMedications.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingMedicationList.toggle()
                        }
                    } label: {
                        Image(systemName: isEditingMedicationList ? "checkmark" : "pencil")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.brandTeal)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isEditingMedicationList ? "完成編輯用藥清單" : "編輯用藥清單")
                }
            }

            ForEach(activeMedications) { med in
                HStack(spacing: 10) {
                    MedicationRow(medication: med)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isEditingMedicationList {
                        Button(role: .destructive) {
                            pendingMedicationDeletion = med
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("刪除 \(med.name)")
                        .transition(.scale.combined(with: .opacity))
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
            if activeMedications.count <= 1 {
                isEditingMedicationList = false
            }
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
struct MedicationRow: View {
    let medication: Medication
    @State private var isExpanded = false
    @Environment(LocaleStore.self) private var localeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
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
                        let freqLabel: String = {
                            switch medication.frequency {
                            case "daily": return localizedFrequencyLabel("每日一次")
                            case "twice_daily": return localizedFrequencyLabel("每日兩次")
                            case "thrice_daily": return localizedFrequencyLabel("每日三次")
                            case "weekly": return localizedFrequencyLabel("每週一次")
                            case "as_needed": return localizedFrequencyLabel("需要時服用")
                            default: return medication.frequency
                            }
                        }()
                        
                        HStack(spacing: 4) {
                            Text("\(medication.dosage) · \(freqLabel)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
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

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

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
                            Text("結束服用日：\(endDate.formatted(date: .long, time: .omitted))")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
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

#Preview {
    NavigationStack {
        MedicationView(userRole: .caregiver)
            .environment(MedicationStore())
            .environment(CareLogStore())
    }
}
