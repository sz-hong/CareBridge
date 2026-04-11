import SwiftUI
import Charts

struct HealthMonitorView: View {
    @State private var selectedRange = 0 // 0=日, 1=週, 2=月
    private let rangeLabels = ["日", "週", "月"]
    @State private var showThresholdSettings = false

    // Sample heart rate data for the week
    private let heartRateData: [(String, Int)] = [
        ("Mon", 74), ("Tue", 78), ("Wed", 82), ("Thu", 112),
        ("Fri", 76), ("Sat", 72), ("Sun", 71),
    ]

    private let bloodOxygenData: [(String, Double)] = [
        ("Mon", 97.5), ("Tue", 98.0), ("Wed", 96.8), ("Thu", 95.2),
        ("Fri", 97.8), ("Sat", 98.2), ("Sun", 97.6),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Range selector
                Picker("範圍", selection: $selectedRange) {
                    ForEach(rangeLabels.indices, id: \.self) { i in
                        Text(rangeLabels[i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Current vitals summary
                HStack(spacing: 12) {
                    vitalCard(title: "心率", value: "72", unit: "bpm",
                              icon: "heart.fill", color: .red, status: "正常")
                    vitalCard(title: "血氧", value: "97.5", unit: "%",
                              icon: "wind", color: Color.brandTeal, status: "最佳")
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    vitalCard(title: "血壓", value: "118/75", unit: "mmHg",
                              icon: "waveform.path.ecg", color: .blue, status: "正常")
                    vitalCard(title: "血糖", value: "5.8", unit: "mmol/L",
                              icon: "drop.fill", color: .orange, status: "正常")
                }
                .padding(.horizontal, 16)

                // Heart Rate Chart
                chartCard(title: "心率趨勢", subtitle: "過去7天 (bpm)", hasAnomaly: true) {
                    Chart {
                        ForEach(heartRateData, id: \.0) { day, rate in
                            BarMark(x: .value("Day", day),
                                    y: .value("BPM", rate))
                            .foregroundStyle(rate > 100 ? Color.red : Color.brandTeal)
                            .cornerRadius(4)
                        }
                        RuleMark(y: .value("Upper", 100))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.red.opacity(0.5))
                        RuleMark(y: .value("Lower", 60))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .frame(height: 160)
                    .chartYScale(domain: 40...140)
                }

                // Blood Oxygen Chart
                chartCard(title: "血氧趨勢", subtitle: "過去7天 (%)", hasAnomaly: false) {
                    Chart {
                        ForEach(bloodOxygenData, id: \.0) { day, value in
                            LineMark(x: .value("Day", day),
                                     y: .value("SpO2", value))
                            .foregroundStyle(Color.brandTeal)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            AreaMark(x: .value("Day", day),
                                     yStart: .value("Min", 93),
                                     yEnd: .value("SpO2", value))
                            .foregroundStyle(Color.brandTeal.opacity(0.1))
                            PointMark(x: .value("Day", day),
                                      y: .value("SpO2", value))
                            .foregroundStyle(value < 95 ? .red : Color.brandTeal)
                            .symbolSize(60)
                        }
                        RuleMark(y: .value("Lower", 93))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .frame(height: 160)
                    .chartYScale(domain: 90...100)
                }

                // Anomaly history
                VStack(alignment: .leading, spacing: 12) {
                    Text("異常紀錄")
                        .font(.system(size: 17, weight: .bold))
                    anomalyRow(
                        title: "心率異常",
                        detail: "心率達到 112 bpm（Thu）",
                        time: "2天前",
                        isConfirmed: true
                    )
                    anomalyRow(
                        title: "血氧偏低",
                        detail: "血氧降至 95.2%（Thu）",
                        time: "2天前",
                        isConfirmed: false
                    )
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("健康監測")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showThresholdSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
        .sheet(isPresented: $showThresholdSettings) {
            HealthThresholdSettingsView()
        }
    }

    private func vitalCard(title: String, value: String, unit: String,
                            icon: String, color: Color, status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
            }
            Text(value)
                .font(.system(size: 26, weight: .bold))
            Text(unit)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white))
    }

    private func chartCard<Content: View>(title: String, subtitle: String,
                                          hasAnomaly: Bool,
                                          @ViewBuilder chart: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hasAnomaly {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("有異常")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                    }
                }
            }
            chart()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
    }

    private func anomalyRow(title: String, detail: String, time: String, isConfirmed: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(time)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if isConfirmed {
                    Text("已確認")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text("待確認")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Health Threshold Settings
struct HealthThresholdSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var heartRateMax: Double = 100
    @State private var heartRateMin: Double = 55
    @State private var bloodOxygenMin: Double = 94
    @State private var bloodPressureSystolicMax: Double = 140
    @State private var bloodPressureDiastolicMax: Double = 90
    @State private var bloodSugarMax: Double = 7.8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("當數值超出警戒範圍時，系統將發送通知給所有家庭成員。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Section("心率 (bpm)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("上限")
                            Spacer()
                            Text("\(Int(heartRateMax)) bpm")
                                .foregroundStyle(.red)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $heartRateMax, in: 80...150, step: 5)
                            .tint(.red)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("下限")
                            Spacer()
                            Text("\(Int(heartRateMin)) bpm")
                                .foregroundStyle(.blue)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $heartRateMin, in: 40...80, step: 5)
                            .tint(.blue)
                    }
                }

                Section("血氧 (SpO2 %)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("最低警戒值")
                            Spacer()
                            Text("\(Int(bloodOxygenMin))%")
                                .foregroundStyle(.orange)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $bloodOxygenMin, in: 88...98, step: 1)
                            .tint(.orange)
                    }
                }

                Section("血壓 (mmHg)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("收縮壓上限")
                            Spacer()
                            Text("\(Int(bloodPressureSystolicMax))")
                                .foregroundStyle(.red)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $bloodPressureSystolicMax, in: 100...180, step: 5)
                            .tint(.red)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("舒張壓上限")
                            Spacer()
                            Text("\(Int(bloodPressureDiastolicMax))")
                                .foregroundStyle(.purple)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $bloodPressureDiastolicMax, in: 60...120, step: 5)
                            .tint(.purple)
                    }
                }

                Section("血糖 (mmol/L)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("餐後上限")
                            Spacer()
                            Text(String(format: "%.1f", bloodSugarMax))
                                .foregroundStyle(.orange)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Slider(value: $bloodSugarMax, in: 5.0...12.0, step: 0.5)
                            .tint(.orange)
                    }
                }
            }
            .navigationTitle("警戒值設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { dismiss() }
                        .bold()
                        .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthMonitorView()
    }
}
