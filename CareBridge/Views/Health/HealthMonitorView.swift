import SwiftUI
import Charts
import HealthKit

// MARK: - HealthKit Manager

@Observable
class HealthKitManager {
    private let store = HKHealthStore()

    var heartRate: Double = 72
    var bloodOxygen: Double = 97.5
    var bloodPressureSystolic: Double = 118
    var bloodPressureDiastolic: Double = 75
    var bloodSugar: Double = 5.8
    var isAuthorized = false

    var heartRateHistory: [(String, Int)] = [
        ("Mon", 74), ("Tue", 78), ("Wed", 82), ("Thu", 112),
        ("Fri", 76), ("Sat", 72), ("Sun", 71)
    ]
    var bloodOxygenHistory: [(String, Double)] = [
        ("Mon", 97.5), ("Tue", 98.0), ("Wed", 96.8), ("Thu", 95.2),
        ("Fri", 97.8), ("Sat", 98.2), ("Sun", 97.6)
    ]

    var heartRateStatus: String { heartRate > 100 || heartRate < 55 ? "異常" : "正常" }
    var bloodOxygenStatus: String { bloodOxygen < 94 ? "偏低" : bloodOxygen >= 98 ? "最佳" : "正常" }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await loadLatestValues()
        } catch { /* 授權失敗時保留 sample 預設值 */ }
    }

    func loadLatestValues() async {
        async let hr   = fetchLatest(.heartRate, unit: HKUnit(from: "count/min"))
        async let spo2 = fetchLatest(.oxygenSaturation, unit: .percent())
        async let sys  = fetchLatest(.bloodPressureSystolic, unit: .millimeterOfMercury())
        async let dia  = fetchLatest(.bloodPressureDiastolic, unit: .millimeterOfMercury())
        async let bg   = fetchLatest(.bloodGlucose, unit: HKUnit(from: "mmol/L"))
        let (hrV, spo2V, sysV, diaV, bgV) = await (hr, spo2, sys, dia, bg)
        if let v = hrV   { heartRate = v }
        if let v = spo2V { bloodOxygen = v * 100 }
        if let v = sysV  { bloodPressureSystolic = v }
        if let v = diaV  { bloodPressureDiastolic = v }
        if let v = bgV   { bloodSugar = v }

        if let hist = await fetchWeekly(.heartRate, unit: HKUnit(from: "count/min")) {
            heartRateHistory = hist.map { ($0.0, Int($0.1)) }
        }
        if let hist = await fetchWeekly(.oxygenSaturation, unit: .percent()) {
            bloodOxygenHistory = hist.map { ($0.0, $0.1 * 100) }
        }
    }

    private func fetchLatest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func fetchWeekly(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> [(String, Double)]? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date())
        let fmt = DateFormatter(); fmt.dateFormat = "E"
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                guard let s = samples as? [HKQuantitySample], !s.isEmpty else { cont.resume(returning: nil); return }
                cont.resume(returning: s.map { (fmt.string(from: $0.startDate), $0.quantity.doubleValue(for: unit)) })
            }
            store.execute(q)
        }
    }
}

// MARK: - Health Monitor View

struct HealthMonitorView: View {
    @State private var selectedRange = 0 // 0=日, 1=週, 2=月
    private let rangeLabels = ["日", "週", "月"]
    @State private var showThresholdSettings = false
    @State private var healthKit = HealthKitManager()

    /// 🔧 Debug toggle for the teal column investigation. Set to true to
    /// render an empty HealthMonitorView and confirm whether the artifact
    /// is from view content or something at the system / NavigationStack
    /// level. Flip back to `false` after the test.
    private let debugIsolate = false

    var body: some View {
        if debugIsolate {
            return AnyView(
                Text("🔧 Debug HealthMonitorView (empty)")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.brandBackground)
                    .navigationTitle("健康監測")
                    .navigationBarTitleDisplayMode(.large)
            )
        }
        return AnyView(realBody)
    }

    private var realBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Range selector — custom segmented control with explicit
                // clipping; iOS 26 Liquid Glass tinting was leaking the
                // selected-segment fill outside the row before.
                rangeSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Current vitals summary (HealthKit 即時數值)
                HStack(spacing: 12) {
                    vitalCard(title: "心率",
                              value: "\(Int(healthKit.heartRate))",
                              unit: "bpm",
                              icon: "heart.fill", color: .red,
                              status: healthKit.heartRateStatus)
                    vitalCard(title: "血氧",
                              value: String(format: "%.1f", healthKit.bloodOxygen),
                              unit: "%",
                              icon: "wind", color: Color.brandTeal,
                              status: healthKit.bloodOxygenStatus)
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    vitalCard(title: "血壓",
                              value: "\(Int(healthKit.bloodPressureSystolic))/\(Int(healthKit.bloodPressureDiastolic))",
                              unit: "mmHg",
                              icon: "waveform.path.ecg", color: .blue,
                              status: "正常")
                    vitalCard(title: "血糖",
                              value: String(format: "%.1f", healthKit.bloodSugar),
                              unit: "mmol/L",
                              icon: "drop.fill", color: .orange,
                              status: "正常")
                }
                .padding(.horizontal, 16)

                // Heart Rate Chart（HealthKit 歷史資料）
                chartCard(title: "心率趨勢", subtitle: "過去7天 (bpm)",
                          hasAnomaly: healthKit.heartRateHistory.contains(where: { $0.1 > 100 })) {
                    Chart {
                        ForEach(healthKit.heartRateHistory, id: \.0) { day, rate in
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

                // Blood Oxygen Chart（HealthKit 歷史資料）
                chartCard(title: "血氧趨勢", subtitle: "過去7天 (%)",
                          hasAnomaly: healthKit.bloodOxygenHistory.contains(where: { $0.1 < 95 })) {
                    Chart {
                        ForEach(healthKit.bloodOxygenHistory, id: \.0) { day, value in
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
        .task { await healthKit.requestAuthorization() }
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

    private var rangeSelector: some View {
        // iOS 26 Liquid Glass had RoundedRectangle.fill leaking past its
        // frame inside a ScrollView. The fix is to:
        //   1. Lock the row height with an explicit `.frame(height:)`
        //   2. Use `Color` (not RoundedRectangle.fill) for the segment fill
        //   3. Apply rounding via `.clipShape` AFTER the fill, so the clip
        //      bounds = the same rect the fill paints into.
        HStack(spacing: 6) {
            ForEach(rangeLabels.indices, id: \.self) { i in
                let isSelected = selectedRange == i
                Button {
                    selectedRange = i
                } label: {
                    Text(rangeLabels[i])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.brandTeal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isSelected ? Color.brandTeal : Color.brandTealLight)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 36)
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
