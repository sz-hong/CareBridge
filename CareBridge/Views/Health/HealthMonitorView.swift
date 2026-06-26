import SwiftUI
import Charts
import HealthKit

// MARK: - HealthKit Manager

@Observable
class HealthKitManager {
    private let store = HKHealthStore()

    // nil = 尚未取得實際讀數（未授權 / 無資料）。一律不顯示假預設值。
    var heartRate: Double?
    var bloodOxygen: Double?
    var bloodSugar: Double?
    var isAuthorized = false

    var heartRateStatus: String {
        guard let hr = heartRate else { return "—" }
        return hr > 100 || hr < 55 ? "異常" : "正常"
    }
    var bloodOxygenStatus: String {
        guard let o = bloodOxygen else { return "—" }
        return o < 94 ? "偏低" : o >= 98 ? "最佳" : "正常"
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
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
        async let bg   = fetchLatest(.bloodGlucose, unit: HKUnit(from: "mmol/L"))
        let (hrV, spo2V, bgV) = await (hr, spo2, bg)
        if let v = hrV   { heartRate = v }
        if let v = spo2V { bloodOxygen = v * 100 }
        if let v = bgV   { bloodSugar = v }
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

}

// MARK: - Health Monitor View

struct HealthMonitorView: View {
    @State private var selectedRange = 0 // 0=日, 1=週, 2=月
    private let rangeLabels = ["日", "週", "月"]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showThresholdSettings = false
    @State private var healthKit = HealthKitManager()
    @State private var liveSocket = HealthLiveSocket()
    @State private var liveBanner: String?
    // 趨勢圖與異常紀錄改抓後端真實資料（家庭範圍，遠端家屬也適用）。
    @State private var heartRateTrend: [HealthHistoryPoint] = []
    @State private var bloodOxygenTrend: [HealthHistoryPoint] = []
    @State private var alerts: [HealthAlert] = []
    @AppStorage("carebridge.healthSyncEnabled") private var healthSyncEnabled = false
    @Environment(CareLogStore.self) private var careLogStore
    @Environment(HealthKitSyncManager.self) private var healthSync
    @Environment(\.dataService) private var service

    /// Most-recent vital reading from CareLog (manual entries via 日誌).
    /// Returns nil for fields the user hasn't logged yet.
    private var latestVital: CareLogEntry? {
        careLogStore.entries
            .filter { $0.type == .vital }
            .sorted { $0.timestamp > $1.timestamp }
            .first(where: { entry in
                // Find the latest vital entry that has *any* of the fields we
                // care about, so blood pressure / sugar fall back independently.
                entry.bloodPressureSystolic != nil ||
                entry.bloodSugar != nil ||
                entry.weight != nil ||
                entry.temperature != nil
            })
    }

    /// Walk all vital entries newest→oldest to surface the most-recent reading
    /// per field individually (so 血壓 from yesterday + 血糖 from today coexist).
    private func latestVital<T>(_ keyPath: KeyPath<CareLogEntry, T?>) -> (value: T, at: Date)? {
        for entry in careLogStore.entries
            .filter({ $0.type == .vital })
            .sorted(by: { $0.timestamp > $1.timestamp }) {
            if let v = entry[keyPath: keyPath] {
                return (v, entry.timestamp)
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            healthContent
        }
        .background(Color.brandBackground)
        .navigationTitle("健康監測")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await healthKit.requestAuthorization()

            // 進入頁面時主動 trigger 一次 HealthKit → backend sync
            // （免費 Apple Developer 帳號無 background delivery 時的兜底）
            await syncHealthIfCurrentOwner()

            // 趨勢圖與異常紀錄抓後端真實資料。
            await loadTrends()

            // Live updates: any family member's HealthKit upload via the
            // /health-data/sync/ endpoint will be fanned out by the backend
            // through ws/health/. Apply incoming points to the local state
            // so the UI stays in sync without manual refresh.
            liveSocket.onUpdate = { update in
                applyLiveUpdate(update)
            }
            liveSocket.connect()
        }
        .refreshable {
            // 下拉重新整理：手動 trigger HealthKit sync + 等 server 回 WS 推送
            await syncHealthIfCurrentOwner()
            await healthKit.loadLatestValues()
            await loadTrends()
        }
        .onDisappear { liveSocket.disconnect() }
        .overlay(alignment: .top) {
            if let liveBanner {
                Text(liveBanner)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.brandTealLight))
                    .foregroundStyle(Color.brandTeal)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
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

    @ViewBuilder
    private var healthContent: some View {
        if usesWideLayout {
            VStack(spacing: 20) {
                rangeSelector
                    .frame(width: 360)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    heartRateVitalCard
                    bloodOxygenVitalCard
                    bloodPressureVitalCard
                    bloodSugarVitalCard
                }

                HStack(alignment: .top, spacing: 20) {
                    heartRateChartCard
                    bloodOxygenChartCard
                }

                anomalySection

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                // Range selector — custom segmented control with explicit
                // clipping; iOS 26 Liquid Glass tinting was leaking the
                // selected-segment fill outside the row before.
                rangeSelector
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    heartRateVitalCard
                    bloodOxygenVitalCard
                }
                .padding(.horizontal, 16)

                HStack(spacing: 12) {
                    bloodPressureVitalCard
                    bloodSugarVitalCard
                }
                .padding(.horizontal, 16)

                heartRateChartCard
                    .padding(.horizontal, 16)

                bloodOxygenChartCard
                    .padding(.horizontal, 16)

                anomalySection
                    .padding(.horizontal, 16)

                Spacer(minLength: 20)
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var heartRateVitalCard: some View {
        vitalCard(
            title: "心率",
            value: healthKit.heartRate.map { "\(Int($0))" } ?? "—",
            unit: "bpm",
            icon: "heart.fill",
            color: .red,
            status: healthKit.heartRateStatus
        )
    }

    private var bloodOxygenVitalCard: some View {
        vitalCard(
            title: "血氧",
            value: healthKit.bloodOxygen.map { String(format: "%.1f", $0) } ?? "—",
            unit: "%",
            icon: "wind",
            color: Color.brandTeal,
            status: healthKit.bloodOxygenStatus
        )
    }

    private var bloodPressureVitalCard: some View {
        let bp = latestVital(\.bloodPressureSystolic)
        let bpd = latestVital(\.bloodPressureDiastolic)
        return vitalCard(
            title: "血壓",
            value: (bp != nil && bpd != nil)
                ? "\(bp!.value)/\(bpd!.value)"
                : "—",
            unit: "mmHg",
            icon: "waveform.path.ecg",
            color: .blue,
            status: bp == nil ? "尚未填寫" : "正常"
        )
    }

    private var bloodSugarVitalCard: some View {
        let sugar = latestVital(\.bloodSugar)
        return vitalCard(
            title: "血糖",
            value: sugar.map { String(format: "%.1f", $0.value) } ?? "—",
            unit: "mmol/L",
            icon: "drop.fill",
            color: .orange,
            status: sugar == nil ? "尚未填寫" : "正常"
        )
    }

    private var heartRateChartCard: some View {
        let hrSeries = chartSeries(heartRateTrend)
        return chartCard(
            title: "心率趨勢",
            subtitle: "過去7天 (bpm)",
            hasAnomaly: hrSeries.contains(where: { $0.1 > 100 })
        ) {
            if hrSeries.isEmpty {
                emptyChart
            } else {
                Chart {
                    ForEach(hrSeries, id: \.0) { day, rate in
                        LineMark(x: .value("Day", day), y: .value("BPM", rate))
                            .foregroundStyle(Color.brandTeal)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(hrSeries, id: \.0) { day, rate in
                        AreaMark(
                            x: .value("Day", day),
                            yStart: .value("Min", 40),
                            yEnd: .value("BPM", rate)
                        )
                        .foregroundStyle(Color.brandTeal.opacity(0.12))
                        .interpolationMethod(.catmullRom)
                    }
                    ForEach(hrSeries, id: \.0) { day, rate in
                        PointMark(x: .value("Day", day), y: .value("BPM", rate))
                            .foregroundStyle(rate > 100 ? Color.red : Color.brandTeal)
                            .symbolSize(60)
                    }
                    RuleMark(y: .value("Upper", 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.red.opacity(0.5))
                    RuleMark(y: .value("Lower", 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.red.opacity(0.5))
                }
                .frame(height: usesWideLayout ? 220 : 160)
                .chartYScale(domain: 40...140)
                .clipped()
                .compositingGroup()
            }
        }
    }

    private var bloodOxygenChartCard: some View {
        let spo2Series = chartSeries(bloodOxygenTrend)
        return chartCard(
            title: "血氧趨勢",
            subtitle: "過去7天 (%)",
            hasAnomaly: spo2Series.contains(where: { $0.1 < 95 })
        ) {
            if spo2Series.isEmpty {
                emptyChart
            } else {
                Chart {
                    ForEach(spo2Series, id: \.0) { day, value in
                        LineMark(x: .value("Day", day), y: .value("SpO2", value))
                            .foregroundStyle(Color.brandTeal)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        AreaMark(
                            x: .value("Day", day),
                            yStart: .value("Min", 93),
                            yEnd: .value("SpO2", value)
                        )
                        .foregroundStyle(Color.brandTeal.opacity(0.1))
                        PointMark(x: .value("Day", day), y: .value("SpO2", value))
                            .foregroundStyle(value < 95 ? .red : Color.brandTeal)
                            .symbolSize(60)
                    }
                    RuleMark(y: .value("Lower", 93))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.red.opacity(0.5))
                }
                .frame(height: usesWideLayout ? 220 : 160)
                .chartYScale(domain: 90...100)
                .clipped()
                .compositingGroup()
            }
        }
    }

    private var anomalySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("異常紀錄")
                .font(.system(size: 17, weight: .bold))
            if alerts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("目前沒有異常紀錄")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(alerts) { alert in
                    anomalyRow(
                        title: alertTitle(alert),
                        detail: alertDetail(alert),
                        time: alert.recordedAt.formatted(.relative(presentation: .named)),
                        isConfirmed: alert.isAcknowledged
                    )
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    private func syncHealthIfCurrentOwner() async {
        guard healthSyncEnabled else { return }
        if let state = try? await service.fetchHealthBinding(), state.isOwner {
            await healthSync.incrementalSyncAll()
        } else {
            healthSyncEnabled = false
        }
    }

    /// 抓後端每日彙整趨勢 + 異常紀錄（家庭範圍，遠端家屬也能看到）。
    private func loadTrends() async {
        async let hr = service.fetchHealthHistory(type: "heart_rate", days: 7)
        async let spo2 = service.fetchHealthHistory(type: "blood_oxygen", days: 7)
        async let al = service.fetchHealthAlerts()
        heartRateTrend = (try? await hr) ?? []
        bloodOxygenTrend = (try? await spo2) ?? []
        alerts = (try? await al) ?? []
    }

    /// 把每日彙整點轉成圖表用的 (星期, 數值) 序列。
    private func chartSeries(_ points: [HealthHistoryPoint]) -> [(String, Double)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "E"
        return points
            .sorted { $0.period < $1.period }
            .map { (fmt.string(from: $0.period), $0.avgValue) }
    }

    /// 趨勢資料為空時的佔位（避免顯示空白座標軸）。
    private var emptyChart: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("尚無趨勢資料")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(height: 160)
    }

    private func alertUnit(_ type: String) -> String {
        switch type {
        case "heart_rate":   return "bpm"
        case "blood_oxygen": return "%"
        default:             return ""
        }
    }

    private func alertTitle(_ alert: HealthAlert) -> String {
        let name = localizedTypeName(alert.type)
        return alert.severity == "critical" ? "\(name)嚴重異常" : "\(name)異常"
    }

    private func alertDetail(_ alert: HealthAlert) -> String {
        let unit = alertUnit(alert.type)
        func fmt(_ v: Double) -> String {
            v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        }
        return "\(localizedTypeName(alert.type)) \(fmt(alert.value))\(unit)（警戒值 \(fmt(alert.threshold))\(unit)）"
    }

    private var rangeSelector: some View {
        // iOS 26 Liquid Glass was applying its own glass background to
        // `Button` views even with `.buttonStyle(.plain)`, causing the
        // selected segment's fill to bleed across the full ScrollView
        // height. We sidestep `Button` entirely with a Rectangle hit area
        // and `.onTapGesture`, plus `.compositingGroup()` to render each
        // segment offscreen first so its fill cannot escape its bounds.
        HStack(spacing: 6) {
            ForEach(rangeLabels.indices, id: \.self) { i in
                let isSelected = selectedRange == i
                Text(rangeLabels[i])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Color.brandTeal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isSelected ? Color.brandTeal : Color.brandTealLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .compositingGroup()
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRange = i }
            }
        }
        .frame(height: 36)
    }

    /// Apply server-pushed health update to the local cards so the UI
    /// reflects watch readings the moment they arrive at the backend.
    private func applyLiveUpdate(_ update: HealthLiveUpdate) {
        for point in update.points {
            switch point.type {
            case "heart_rate":             healthKit.heartRate = point.value
            case "blood_oxygen":           healthKit.bloodOxygen = point.value
            default: break
            }
        }
        if let mostRecent = update.points.max(by: { $0.recordedAt < $1.recordedAt }) {
            withAnimation { liveBanner = "新數據：\(localizedTypeName(mostRecent.type)) \(Int(mostRecent.value))" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { liveBanner = nil }
            }
        }
    }

    private func localizedTypeName(_ type: String) -> String {
        switch type {
        case "heart_rate":               return "心率"
        case "blood_oxygen":             return "血氧"
        case "step_count":               return "步數"
        case "active_energy":            return "活動熱量"
        default: return type
        }
    }

    /// 依狀態字串決定徽章顏色：異常/偏低→橘、尚未填寫/—→灰、其餘→綠。
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "異常", "偏低":      return .orange
        case "尚未填寫", "—":     return .secondary
        default:                  return .green
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
                    Circle().fill(statusColor(status)).frame(width: 5, height: 5)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(statusColor(status))
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
    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var heartRateMax: Double = 100
    @State private var heartRateMin: Double = 55
    @State private var bloodOxygenMin: Double = 94
    @State private var bloodPressureSystolicMax: Double = 140
    @State private var bloodPressureDiastolicMax: Double = 90
    @State private var bloodSugarMax: Double = 7.8
    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                }

                if false {
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
                }

                if false {
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
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("警戒值設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { Task { await saveThresholds() } }
                        .bold()
                        .foregroundStyle(Color.brandTeal)
                        .disabled(isSaving)
                }
            }
            .task { await loadThresholds() }
        }
    }

    @MainActor
    private func loadThresholds() async {
        do {
            let thresholds = try await service.fetchHealthThresholds()
            heartRateMax = Double(thresholds.heartRateHigh)
            heartRateMin = Double(thresholds.heartRateLow)
            bloodOxygenMin = thresholds.bloodOxygenLow
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveThresholds() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.updateHealthThresholds(
                HealthAlertThresholdSettings(
                    heartRateHigh: Int(heartRateMax),
                    heartRateLow: Int(heartRateMin),
                    bloodOxygenLow: bloodOxygenMin
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        HealthMonitorView()
    }
}
