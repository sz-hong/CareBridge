import SwiftUI
import Charts
import Vision
import VisionKit
import PhotosUI
import UIKit

struct SpendingView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    var isEmbeddedInManagement = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.floatingActionBottomPadding) private var floatingActionBottomPadding
    @Environment(\.dataService) private var service
    @State private var expenses: [Expense] = []
    @State private var summary: SpendingSummary? = nil
    @State private var showAllExpenses = false
    @State private var showDocumentCamera = false   // 直接開啟掃描器
    @State private var showOCRConfirmation = false
    @State private var pendingOCRResult: OCRResult? = nil
    @State private var receiptStage: ScanStage = .idle
    @State private var showNotifications = false
    @State private var showExportSheet = false
    @State private var exportItems: [Any] = []

    var body: some View {
        if isEmbeddedInManagement {
            spendingSurface
        } else {
            NavigationStack {
                spendingSurface
            }
        }
    }

    private var spendingSurface: some View {
        Group {
            ScrollView {
                VStack(spacing: 20) {
                    if !isEmbeddedInManagement {
                        // Header with label
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CAREBRIDGE WALLET")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.5)
                                Text("消費記帳")
                                    .font(.system(size: 28, weight: .bold))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, usesWideLayout ? 32 : 16)
                        .padding(.top, usesWideLayout ? 16 : 8)
                        .frame(maxWidth: usesWideLayout ? 1180 : .infinity)
                        .frame(maxWidth: .infinity)
                    }

                    spendingContent

                    Spacer(minLength: 80)
                }
            }
        }
        .background(Color.brandBackground)
        .scrollIndicators(.hidden)
        .toolbar {
            if !isEmbeddedInManagement {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        HStack(spacing: 0) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.brandTeal)
                            Text("CareBridge")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if !isEmbeddedInManagement {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        NotificationBellButton { showNotifications = true }
                        Button {
                            exportItems = [generateCSV()]
                            showExportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Both caregivers and family members may record expenses.
            Button {
                showDocumentCamera = true
            } label: {
                ZStack {
                    Circle()
                        .fill(receiptStage == .idle ? Color.brandTeal : Color.gray)
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    Image(systemName: receiptStage == .idle ? "doc.viewfinder.fill" : "ellipsis")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .disabled(receiptStage != .idle)
            .padding(.trailing, usesWideLayout ? 32 : 20)
            .padding(.bottom, floatingActionBottomPadding)
            .accessibilityLabel("新增記帳")
        }
        // 直接開啟原生文件掃描器
        .fullScreenCover(isPresented: $showDocumentCamera) {
            DocumentCameraView(
                onCapture: { image in
                    showDocumentCamera = false
                    processReceipt(image)
                },
                onCancel: { showDocumentCamera = false }
            )
            .ignoresSafeArea()
        }
        // 掃描完成後顯示確認頁
        .sheet(isPresented: $showOCRConfirmation) {
            if let result = pendingOCRResult {
                OCRConfirmationView(ocrResult: result) { newExpense in
                    expenses.insert(newExpense, at: 0)
                    // Summary 是後端彙算的（含分類百分比），不能只加本地值
                    // ——必須重新打 /expenses/monthly/ 讓卡片與甜甜圈同步刷新。
                    Task {
                        summary = try? await service.fetchSpendingSummary(month: nil)
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ShareSheet(items: exportItems)
        }
        .navigationDestination(isPresented: $showNotifications) {
            NotificationCenterView()
        }
        .navigationDestination(isPresented: $showAllExpenses) {
            AllExpensesView()
        }
        .task {
            async let e = service.fetchExpenses(month: nil)
            async let s = service.fetchSpendingSummary(month: nil)
            expenses = (try? await e) ?? []
            summary  = try? await s
        }
    }

    @ViewBuilder
    private var spendingContent: some View {
        if usesWideLayout {
            HStack(alignment: .top, spacing: 20) {
                monthlyCard
                    .frame(maxWidth: 420)
                recentTransactions
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 20) {
                monthlyCard
                    .padding(.horizontal, 16)
                recentTransactions
                    .padding(.horizontal, 16)
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    // MARK: - CSV Export

    private func generateCSV() -> URL {
        var csv = "日期,名稱,類別,金額(TWD)\n"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for exp in expenses {
            csv += "\(fmt.string(from: exp.date)),\(exp.title),\(Expense.localizedCategoryName(exp.category)),\(Int(exp.amount))\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CareBridge_消費記錄.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Process Receipt (去背 + OCR)

    private func processReceipt(_ image: UIImage) {
        Task {
            await MainActor.run { receiptStage = .removingBackground }
            let bgRemoved = await BackgroundRemover.remove(from: image)
            await MainActor.run { receiptStage = .recognizingText }
            var result = await OCRProcessor.recognize(image: image)
            result.image = bgRemoved
            await MainActor.run {
                receiptStage = .idle
                pendingOCRResult = result
                showOCRConfirmation = true
            }
        }
    }

    // MARK: - Chart Helpers

    private struct LegendItem: Identifiable {
        let id = UUID()
        let key: LocalizedStringKey
        let percentage: Double
        let color: Color
    }

    /// Backend 已正規化分類成 wire codes（medical / food / daily / transport /
    /// other），這裡只負責決定顏色。顯示名稱統一交給 LocalizedStringKey。
    private func colorForCategory(_ wireCode: String) -> Color {
        switch wireCode {
        case "medical":   return .brandTeal
        case "food":      return .orange
        case "daily":     return .purple
        case "transport": return .blue
        case "other":     return .pink
        default:          return Color(.systemGray4)
        }
    }

    private var hasSpendingBreakdown: Bool {
        guard let summary,
              summary.monthlyTotal > 0,
              !summary.categoryBreakdown.isEmpty else {
            return false
        }
        return summary.categoryBreakdown.contains { $0.percentage > 0 }
    }

    private func donutSegments() -> [(from: Double, to: Double, color: Color)] {
        guard hasSpendingBreakdown,
              let items = summary?.categoryBreakdown else {
            return [(0, 1, Color(.systemGray5))]
        }
        var segs: [(Double, Double, Color)] = []
        var acc: Double = 0
        for item in items {
            let frac = item.percentage / 100.0
            guard frac > 0 else { continue }
            segs.append((acc, acc + frac, colorForCategory(item.category)))
            acc += frac
        }
        return segs.isEmpty ? [(0, 1, Color(.systemGray5))] : segs
    }

    private func legendItems() -> [LegendItem] {
        guard hasSpendingBreakdown,
              let items = summary?.categoryBreakdown else {
            return []
        }
        return items.filter { $0.percentage > 0 }.map {
            LegendItem(key: Expense.localizedCategoryKey($0.category),
                       percentage: $0.percentage,
                       color: colorForCategory($0.category))
        }
    }

    // MARK: - Monthly Card
    private var monthlyCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本月支出總計")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("NT$ \(Int(summary?.monthlyTotal ?? 0).formatted())")
                        .font(.system(size: 34, weight: .bold))
                }
                Spacer()
                Button {
                    // Show full report
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .frame(width: 40, height: 40)
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }

            // Donut chart
            ZStack {
                ForEach(donutSegments().indices, id: \.self) { i in
                    let seg = donutSegments()[i]
                    Circle()
                        .trim(from: seg.from, to: seg.to)
                        .stroke(seg.color, lineWidth: 20)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 2) {
                    Text(Date().formatted(.dateTime.month(.wide)).uppercased())
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(Calendar.current.component(.year, from: Date())))
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .frame(width: 160, height: 160)
            .padding(.vertical, 8)

            // Legend
            if hasSpendingBreakdown {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(legendItems()) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.key)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(item.percentage))%")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Spacer()
                        }
                    }
                }
            } else {
                Text("本月尚無支出紀錄")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }

    // MARK: - Recent Transactions
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近交易")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button { showAllExpenses = true } label: {
                    Text("查看全部")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandTeal)
                }
            }

            ForEach(expenses) { expense in
                NavigationLink {
                    ExpenseDetailView(expense: expense)
                } label: {
                    ExpenseRow(expense: expense)
                }
                .buttonStyle(.plain)
                if expense.id != expenses.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
    }
}

// MARK: - Expense Row
struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(expense.categoryColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: expense.categoryIcon)
                    .foregroundStyle(expense.categoryColor)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    if Calendar.current.isDateInToday(expense.date) {
                        Text("今天")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(expense.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Text("- TWD \(Int(expense.amount).formatted())")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                // 去背發票縮圖（有掃描才顯示）
                if let img = expense.receiptImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(.systemGray4), lineWidth: 0.5)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray6))
                        )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - OCR Result Model
struct OCRResult {
    var storeName: String
    var amount: String
    var date: Date
    var rawText: String
    var image: UIImage
}

// MARK: - OCR Processor
enum OCRProcessor {
    static func recognize(image: UIImage) async -> OCRResult {
        guard let cgImage = image.cgImage else {
            return OCRResult(storeName: "", amount: "", date: Date(), rawText: "", image: image)
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(storeName: "", amount: "", date: Date(), rawText: "", image: image))
                    return
                }

                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let rawText = lines.joined(separator: "\n")
                let (storeName, amount, date) = parseReceipt(lines: lines)

                continuation.resume(returning: OCRResult(
                    storeName: storeName,
                    amount: amount,
                    date: date ?? Date(),
                    rawText: rawText,
                    image: image
                ))
            }

            // 支援繁中、簡中、英文識別
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: imageOrientation(from: image), options: [:])
            try? handler.perform([request])
        }
    }

    private static func imageOrientation(from image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }

    // 從 OCR 文字行中解析商家名稱、總金額、日期
    private static func parseReceipt(lines: [String]) -> (storeName: String, amount: String, date: Date?) {
        // 商家名稱：取第一個有意義的行（長度 > 2）
        let storeName = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).count > 2 }) ?? ""

        // 總金額：尋找關鍵字後的最大數字
        var amount = ""
        let totalKeywords = ["總計", "合計", "小計", "應付", "實收", "TOTAL", "Total", "total", "AMOUNT"]
        for line in lines {
            let matched = totalKeywords.contains(where: { line.contains($0) })
            if matched {
                let numbers = extractNumbers(from: line)
                if let largest = numbers.max(), largest > 0 {
                    amount = String(format: "%.0f", largest)
                    break
                }
            }
        }

        // 若無關鍵字，找所有行中最大金額（排除年份等大數字）
        if amount.isEmpty {
            var maxAmount: Double = 0
            for line in lines {
                let numbers = extractNumbers(from: line)
                if let max = numbers.max(), max > maxAmount, max < 100_000, max >= 1 {
                    maxAmount = max
                    amount = String(format: "%.0f", max)
                }
            }
        }

        // 日期解析：優先西元年 yyyy-MM-dd（含時間戳），其次民國年完整日期（排除期別如 115年03-04月）
        var date: Date? = nil

        // Step 1：找西元年格式 yyyy-MM-dd 或 yyyy/MM/dd（後面可接 HH:mm:ss）
        let isoPattern = "\\b(\\d{4})[\\-/](\\d{1,2})[\\-/](\\d{1,2})(?:\\s+\\d{1,2}:\\d{2}:\\d{2})?"
        if let isoRegex = try? NSRegularExpression(pattern: isoPattern) {
            outer: for line in lines {
                let nsLine = line as NSString
                let nsRange = NSRange(location: 0, length: nsLine.length)
                for match in isoRegex.matches(in: line, range: nsRange) {
                    guard match.numberOfRanges >= 4 else { continue }
                    let yr = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
                    let mo = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
                    let dy = Int(nsLine.substring(with: match.range(at: 3))) ?? 0
                    guard yr >= 2000, mo >= 1, mo <= 12, dy >= 1, dy <= 31 else { continue }
                    var comps = DateComponents()
                    comps.year = yr; comps.month = mo; comps.day = dy
                    date = Calendar.current.date(from: comps)
                    if date != nil { break outer }
                }
            }
        }

        // Step 2：若無西元年，找民國年完整日期（需有「日」，排除「115年03-04月」期別格式）
        if date == nil {
            let rocPattern = "(\\d{2,3})年(\\d{1,2})月(\\d{1,2})日?"
            if let rocRegex = try? NSRegularExpression(pattern: rocPattern) {
                for line in lines {
                    let range = NSRange(line.startIndex..., in: line)
                    if let match = rocRegex.firstMatch(in: line, range: range),
                       let swiftRange = Range(match.range, in: line) {
                        date = parseDate(String(line[swiftRange]))
                        if date != nil { break }
                    }
                }
            }
        }

        return (storeName, amount, date)
    }

    private static func extractNumbers(from text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: "[0-9,]+\\.?[0-9]*") else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsRange).compactMap { match -> Double? in
            guard let r = Range(match.range, in: text) else { return nil }
            return Double(text[r].replacingOccurrences(of: ",", with: ""))
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        // 去除時間部分（如 "2026-03-15 00:19:09" → "2026-03-15"）
        let dateOnly = raw.components(separatedBy: " ").first ?? raw

        // 統一格式：把中文符號換成 /
        let cleaned = dateOnly
            .replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")
            .replacingOccurrences(of: "-", with: "/")

        let parts = cleaned.split(separator: "/")
        guard let yearPart = parts.first, let year = Int(yearPart) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // 民國年轉西元
        if year < 200 {
            let gregorianYear = year + 1911
            let rest = parts.dropFirst().joined(separator: "/")
            formatter.dateFormat = "yyyy/M/d"
            return formatter.date(from: "\(gregorianYear)/\(rest)")
        }

        for fmt in ["yyyy/M/d", "yyyy/MM/dd"] {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: cleaned) { return d }
        }
        return nil
    }
}

// MARK: - Document Camera（UIImagePickerController 單張拍照）
// 改用 UIImagePickerController 而非 VNDocumentCameraViewController：
// VNDocument 的多頁 Save 流程強制要按右上打勾，使用者反映繁瑣。改成
// 單張拍照 → "Use Photo" → 立刻進 OCR 確認頁，少一個點擊。

struct DocumentCameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

// MARK: - Background Remover（VNGenerateForegroundInstanceMaskRequest）

enum BackgroundRemover {
    /// 使用 Vision 框架移除影像背景，保留發票前景並輸出透明背景 UIImage
    static func remove(from image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let result = request.results?.first as? VNInstanceMaskObservation else { return image }
            let maskedBuffer = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            let context = CIContext()
            guard let cgOut = context.createCGImage(ciImage, from: ciImage.extent) else { return image }
            return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
        } catch {
            return image   // 去背失敗時原圖退回
        }
    }
}

// MARK: - Receipt Scanner View

private enum ScanStage {
    case idle, removingBackground, recognizingText
    var label: String {
        switch self {
        case .idle: return ""
        case .removingBackground: return "去背中…"
        case .recognizingText: return "OCR 辨識中…"
        }
    }
}

struct ReceiptScannerView: View {
    var onAdd: (Expense) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var originalImage: UIImage? = nil       // 原始掃描圖（供 OCR）
    @State private var processedImage: UIImage? = nil      // 去背後圖（顯示 + 存入記錄）
    @State private var stage: ScanStage = .idle
    @State private var ocrResult: OCRResult? = nil
    @State private var showOCRConfirmation = false

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 預覽區域
                ZStack {
                    // 背景（棋盤格顯示透明感）
                    if processedImage != nil {
                        CheckerboardBackground()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    }

                    if let img = processedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else if originalImage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.brandTeal)
                            Text("點下方按鈕掃描發票")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 處理中 overlay
                    if stage != .idle {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.55))
                            .overlay {
                                VStack(spacing: 14) {
                                    ProgressView().tint(.white).scaleEffect(1.5)
                                    Text(stage.label)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
                .frame(height: 300)
                .frame(maxWidth: usesWideLayout ? 560 : .infinity)
                .padding(.horizontal, 32)

                Text("自動去背 + Vision OCR 辨識金額與品項")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // 掃描按鈕
                Button { showCamera = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.viewfinder.fill")
                        Text(originalImage == nil ? "掃描發票" : "重新掃描")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.brandTeal))
                }
                .buttonStyle(.plain)
                .disabled(stage != .idle)

                // 相簿（模擬器備用）
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("從相簿選擇")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandTeal)
                }
                .disabled(stage != .idle)

                Spacer()
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .navigationTitle("掃描發票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.primary)
                    }
                }
            }
            // 文件掃描器（原生 UI）
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView(
                    onCapture: { image in
                        showCamera = false
                        processReceipt(image)
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            // 相簿選取
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    processReceipt(img)
                }
            }
            // 確認頁
            .sheet(isPresented: $showOCRConfirmation) {
                if let result = ocrResult {
                    OCRConfirmationView(ocrResult: result, onSave: { expense in
                        onAdd(expense)
                        dismiss()
                    })
                }
            }
        }
    }

    /// 去背 → OCR → 顯示確認頁
    private func processReceipt(_ image: UIImage) {
        originalImage = image
        processedImage = nil

        Task {
            // Step 1: 去背
            await MainActor.run { stage = .removingBackground }
            let bgRemoved = await BackgroundRemover.remove(from: image)
            await MainActor.run { processedImage = bgRemoved }

            // Step 2: OCR（在原圖上執行以保留最佳辨識率）
            await MainActor.run { stage = .recognizingText }
            var result = await OCRProcessor.recognize(image: image)
            result.image = bgRemoved   // 在確認頁顯示去背版

            await MainActor.run {
                stage = .idle
                ocrResult = result
                showOCRConfirmation = true
            }
        }
    }
}

// 棋盤格背景（顯示透明感）
private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 10
            for row in 0...Int(size.height / tile) {
                for col in 0...Int(size.width / tile) {
                    let isLight = (row + col) % 2 == 0
                    ctx.fill(
                        Path(CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(isLight ? Color(.systemGray5) : Color(.systemGray6))
                    )
                }
            }
        }
    }
}

// MARK: - OCR Confirmation View
struct OCRConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let ocrResult: OCRResult
    let onSave: (Expense) -> Void

    @State private var storeName: String
    @State private var totalAmount: String
    @State private var receiptDate: Date
    @State private var category = "food"
    @State private var note = ""
    @State private var showRawText = false
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isAmountFocused: Bool

    private let categories: [String] = Expense.allCategoryCodes

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    init(ocrResult: OCRResult, onSave: @escaping (Expense) -> Void) {
        self.ocrResult = ocrResult
        self.onSave = onSave
        _storeName = State(initialValue: ocrResult.storeName)
        _totalAmount = State(initialValue: ocrResult.amount)
        _receiptDate = State(initialValue: ocrResult.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                // 狀態列
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: ocrResult.amount.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                            .foregroundStyle(ocrResult.amount.isEmpty ? .orange : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ocrResult.amount.isEmpty ? "部分辨識，請手動補充" : "OCR 辨識完成")
                                .font(.system(size: 15, weight: .semibold))
                            Text("請確認或修正以下資訊")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 收據縮圖
                Section("收據圖片") {
                    HStack {
                        Spacer()
                        Image(uiImage: ocrResult.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // 辨識結果（可編輯）
                Section("收據資訊") {
                    LabeledContent("商家名稱") {
                        TextField("商家名稱", text: $storeName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("金額（NT$）") {
                        TextField("金額", text: $totalAmount)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($isAmountFocused)
                    }
                    DatePicker("消費日期", selection: $receiptDate, displayedComponents: .date)
                }

                Section("分類與備註") {
                    Picker("分類", selection: $category) {
                        ForEach(categories, id: \.self) { code in
                            Text(Expense.localizedCategoryKey(code)).tag(code)
                        }
                    }
                    TextField("備註（選填）", text: $note)
                }

                // 展開原始 OCR 文字（供手動查閱）
                if !ocrResult.rawText.isEmpty {
                    Section {
                        DisclosureGroup("查看 OCR 原始文字", isExpanded: $showRawText) {
                            Text(ocrResult.rawText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: usesWideLayout ? 640 : .infinity)
            .frame(maxWidth: .infinity)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("確認收據資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "儲存中…" : "儲存") { save() }
                        .bold().foregroundStyle(Color.brandTeal)
                        .disabled(isSaving || (storeName.isEmpty && totalAmount.isEmpty))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if isAmountFocused {
                        Spacer()
                        KeyboardDoneButton {
                            isAmountFocused = false
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .alert("儲存失敗", isPresented: .constant(saveError != nil)) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    /// Upload the scanned image to object storage, then create the expense on the
    /// backend. Only dismiss + notify caller on full success so the receipt
    /// photo is guaranteed to persist across app launches.
    private func save() {
        isSaving = true
        Task {
            do {
                let uploadReference = try await service.uploadReceiptImage(ocrResult.image)
                let draft = Expense(
                    id: UUID().uuidString,
                    title: storeName.isEmpty ? "未命名收據" : storeName,
                    amount: Double(totalAmount) ?? 0,
                    category: category,
                    date: receiptDate,
                    hasReceipt: true,
                    rawImageKey: uploadReference.rawKey,
                    receiptImage: ocrResult.image
                )
                let created = try await service.createExpense(draft)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    onSave(created)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController 包裝)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - All Expenses View
struct AllExpensesView: View {
    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var expenses: [Expense] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d"
        return f
    }()

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        List(expenses) { expense in
            NavigationLink {
                ExpenseDetailView(expense: expense)
            } label: {
                ExpenseRow(expense: expense)
            }
            .listRowBackground(Color.white)
            .listRowSeparatorTint(Color(.systemGray5))
        }
        .listStyle(.plain)
        .frame(maxWidth: usesWideLayout ? 900 : .infinity)
        .frame(maxWidth: .infinity)
        .background(Color.brandBackground)
        .navigationTitle("消費記錄")
        .navigationBarTitleDisplayMode(.large)
        .task {
            expenses = (try? await service.fetchExpenses(month: nil)) ?? []
        }
    }
}

// MARK: - Expense Detail View
struct ExpenseDetailView: View {
    let expense: Expense
    @Environment(\.dataService) private var service
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 進入這個畫面時才向 backend 拿 presigned image URL —— list 端點為了
    /// 省下每筆 SigV4 簽名請求已經不回傳，這裡才補拉。
    @State private var resolvedImageUrl: String?
    @State private var isFetchingImage = false

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                receiptImageSection

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "商家", value: expense.title)
                    Divider()
                    detailRow(label: "金額", value: "NT$ \(Int(expense.amount).formatted())")
                    Divider()
                    detailRow(
                        label: "分類",
                        value: expense.category.isEmpty ? "—" : Expense.localizedCategoryName(expense.category),
                    )
                    Divider()
                    detailRow(label: "日期", value: expense.date.formatted(date: .long, time: .shortened))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: usesWideLayout ? 760 : .infinity)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(Color.brandBackground)
        .navigationTitle("消費詳情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 只有確實有發票才打 detail；剛拍完的（receiptImage 在記憶體）也不必再打。
            guard expense.receiptImage == nil,
                  expense.hasReceipt,
                  resolvedImageUrl == nil,
                  !isFetchingImage else { return }
            isFetchingImage = true
            defer { isFetchingImage = false }
            if let fresh = try? await service.fetchExpense(id: expense.id) {
                resolvedImageUrl = fresh.imageUrl
            }
        }
    }

    @ViewBuilder
    private var receiptImageSection: some View {
        // Prefer the in-memory UIImage if the user just captured this expense;
        // otherwise fall back to the presigned URL fetched on appear.
        if let img = expense.receiptImage {
            receiptImage(Image(uiImage: img))
        } else if isFetchingImage {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        } else if let urlStr = resolvedImageUrl ?? expense.imageUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    receiptImage(image)
                case .failure:
                    receiptPlaceholder(icon: "exclamationmark.triangle", text: "收據圖片載入失敗")
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 240)
                @unknown default:
                    receiptPlaceholder(icon: "photo", text: "無收據圖片")
                }
            }
        } else {
            receiptPlaceholder(icon: "photo", text: "無收據圖片")
        }
    }

    private func receiptImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
    }

    private func receiptPlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
        .padding(.horizontal, 16)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
        }
    }
}

#Preview {
    SpendingView(showProfile: .constant(false), userRole: .family)
        .environment(NotificationStore(service: MockDataService()))
}
