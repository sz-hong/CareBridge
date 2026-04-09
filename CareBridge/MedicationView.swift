import SwiftUI

struct MedicationView: View {
    @State private var medications = Medication.samples
    @State private var showAddMedication = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Today's summary
                todaySummaryCard

                // Medication list
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("目前用藥清單")
                            .font(.system(size: 17, weight: .bold))
                        Spacer()
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

                    ForEach(medications) { med in
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
            Text("新增藥物")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.brandBackground)
        }
    }

    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日服藥進度")
                .font(.system(size: 17, weight: .bold))

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2 / 3")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.brandTeal)
                    Text("已服用")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: 0.67)
                        .stroke(Color.brandTeal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 64, height: 64)
            }

            // Timeline
            VStack(spacing: 0) {
                doseRow(time: "08:00", name: "晨間藥物 x3", isDone: true)
                Divider().padding(.leading, 44)
                doseRow(time: "14:00", name: "Metformin 500mg", isDone: false)
                Divider().padding(.leading, 44)
                doseRow(time: "18:00", name: "晚間藥物 x2", isDone: false)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
    }

    private func doseRow(time: String, name: String, isDone: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.brandTeal : Color(.systemGray4))
                    .frame(width: 28, height: 28)
                Image(systemName: isDone ? "checkmark" : "clock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(time)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, alignment: .leading)
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(isDone ? .secondary : .primary)
            Spacer()
            if isDone {
                Text("已服用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
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
                        Text("\(medication.dosage) · \(medication.frequency)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(medication.times, id: \.self) { time in
                            Text(time)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.brandTealLight))
                                .foregroundStyle(Color.brandTeal)
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

#Preview {
    NavigationStack {
        MedicationView()
    }
}
