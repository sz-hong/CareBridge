import SwiftUI

struct MedicationView: View {
    var userRole: UserRole = .family
    @Environment(MedicationStore.self) private var medStore
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(CalendarStore.self) private var calendarStore
    @State private var showAddMedication = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todaySummaryCard

                // Medication list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("目前用藥清單")
                            .font(.system(size: 17, weight: .bold))
                        Spacer()
                        if userRole == .family{
                            Button {
                                showAddMedication = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("新增")
                                }
                                .font(.system(size: 14))
                                .foregroundStyle(Color.brandTeal)
                            }
                        }
                    }

                    ForEach(medStore.medications) { med in
                        MedicationRow(medication: med)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
            .padding(.top, 8)
        }
        .background(Color.brandBackground)
        .navigationTitle("用藥管理")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showAddMedication) {
            AddMedicationView { newMed, calEvents in
                medStore.addMedication(newMed)
                calendarStore.addEvents(calEvents)
            }
        }
        .task { medStore.load() }
    }

    // MARK: - Today's Summary
    private var todaySummaryCard: some View {
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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
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
                    markDoseAsTaken(index: index)
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

    private func markDoseAsTaken(index: Int) {
        let dose = medStore.doses[index]

        withAnimation(.easeInOut(duration: 0.3)) {
            medStore.markDoseTaken(index: index)
        }

        // Auto-create care log entry
        let entry = CareLogEntry(
            id: UUID().uuidString,
            type: .medication,
            title: "\(dose.name) 已服用",
            detail: "\(dose.time) 服藥完成",
            timestamp: Date(),
            hasPhoto: false
        )
        careLogStore.addEntry(entry)
    }
}

// MARK: - Medication Row
struct MedicationRow: View {
    let medication: Medication
    @State private var isExpanded = false

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
                        HStack(spacing: 4) {
                            Text("\(medication.dosage) · \(medication.frequency)")
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
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                        Text(medication.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
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
}

// MARK: - Add Medication View
struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (Medication, [CalendarEvent]) -> Void

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
                            Text(frequencyLabels[i]).tag(i)
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
        let med = Medication(
            id: UUID().uuidString,
            name: name.isEmpty ? nameTranslated : name,
            nameTranslated: nameTranslated.isEmpty ? name : nameTranslated,
            dosage: dosage.isEmpty ? "—" : dosage,
            frequency: frequencyLabels[frequency],
            times: times,
            notes: notes,
            isActive: true
        )

        var calEvents: [CalendarEvent] = []
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endDay = calendar.startOfDay(for: endDate)
        var currentDay = startOfToday

        while currentDay <= endDay {
            for timeStr in times {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                if let eventDate = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: currentDay) {
                    let event = CalendarEvent(
                        id: UUID().uuidString,
                        title: "💊 \(med.nameTranslated) \(med.dosage)",
                        date: eventDate,
                        location: nil,
                        type: "用藥"
                    )
                    calEvents.append(event)
                }
            }
            currentDay = calendar.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay.addingTimeInterval(86400)
        }

        onAdd(med, calEvents)
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
            .environment(CalendarStore())
    }
}
