import SwiftUI
import Charts
import Vision
import PhotosUI
import UIKit

struct SpendingView: View {
    @Binding var showProfile: Bool
    let userRole: UserRole
    @State private var expenses = Expense.samples
    @State private var showReceiptScanner = false
    @State private var showNotifications = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Monthly total card
                    monthlyCard

                    // Recent transactions
                    recentTransactions

                    Spacer(minLength: 80)
                }
            }
            .background(Color.brandBackground)
            .scrollIndicators(.hidden)
            .toolbar {
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
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.brandTeal)
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        Button { } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandTeal)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if userRole == .caregiver {
                    HStack(spacing: 12) {
                        Button {
                            showReceiptScanner = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16))
                                Text("拍攝收據")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.brandTeal))
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
            .sheet(isPresented: $showReceiptScanner) {
                ReceiptScannerView()
            }
            .navigationDestination(isPresented: $showNotifications) {
                NotificationCenterView()
            }
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
                    Text("NT$ \(Int(Expense.monthlyTotal).formatted())")
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

            // Donut chart simulation
            ZStack {
                // Outer ring segments
                Circle()
                    .trim(from: 0, to: 0.45)
                    .stroke(Color.brandTeal, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.45, to: 0.70)
                    .stroke(Color.orange, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.70, to: 0.90)
                    .stroke(Color.purple, lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.90, to: 1.0)
                    .stroke(Color(.systemGray4), lineWidth: 20)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("AUGUST")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("2024")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .frame(width: 160, height: 160)
            .padding(.vertical, 8)

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Expense.categoryBreakdown, id: \.0) { name, pct, color in
                    HStack(spacing: 8) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("\(Int(pct))%")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
    }

    // MARK: - Recent Transactions
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近交易")
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    // Show all
                } label: {
                    Text("查看全部")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.brandTeal)
                }
            }

            ForEach(expenses) { expense in
                ExpenseRow(expense: expense)
                if expense.id != expenses.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .padding(.horizontal, 16)
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

            Text("- TWD \(Int(expense.amount).formatted())")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
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

// MARK: - Camera Picker（UIImagePickerController 包裝）
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // 模擬器沒有相機，自動 fallback 到相簿
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.capturedImage = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Receipt Scanner View
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var capturedImage: UIImage? = nil
    @State private var isProcessing = false
    @State private var ocrResult: OCRResult? = nil
    @State private var showOCRConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // 預覽區域：拍攝前顯示導引框，拍攝後顯示縮圖
                ZStack {
                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                            .frame(height: 280)
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(Color.brandTeal)
                                    Text("對準收據拍攝")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        // 導引框
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.brandTeal, lineWidth: 3)
                            .frame(width: 220, height: 160)
                    }

                    // OCR 處理中 overlay
                    if isProcessing {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.black.opacity(0.5))
                            .frame(height: 280)
                            .overlay {
                                VStack(spacing: 14) {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.5)
                                    Text("OCR 辨識中…")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                }
                .padding(.horizontal, 32)

                Text("Vision OCR 自動辨識收據金額與品項")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                // 拍攝按鈕
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("拍攝收據")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.brandTeal))
                }
                .buttonStyle(.plain)

                // 從相簿選擇
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("從相簿選擇")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandTeal)
                }

                Spacer()
            }
            .navigationTitle("拍攝收據")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.primary)
                    }
                }
            }
            // 相機
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(capturedImage: $capturedImage).ignoresSafeArea()
            }
            // 拍攝完成 → 跑 OCR
            .onChange(of: capturedImage) { _, newImage in
                guard let img = newImage else { return }
                runOCR(on: img)
            }
            // 相簿選完 → 解碼 → 跑 OCR
            .onChange(of: selectedPhotoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let img = UIImage(data: data) else { return }
                    capturedImage = img
                }
            }
            // OCR 完成 → 跳確認頁
            .sheet(isPresented: $showOCRConfirmation) {
                if let result = ocrResult {
                    OCRConfirmationView(ocrResult: result) { dismiss() }
                }
            }
        }
    }

    private func runOCR(on image: UIImage) {
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            let result = await OCRProcessor.recognize(image: image)
            await MainActor.run {
                isProcessing = false
                ocrResult = result
                showOCRConfirmation = true
            }
        }
    }
}

// MARK: - OCR Confirmation View
struct OCRConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    let ocrResult: OCRResult
    let onSave: () -> Void

    @State private var storeName: String
    @State private var totalAmount: String
    @State private var receiptDate: Date
    @State private var category = "日常用品"
    @State private var note = ""
    @State private var showRawText = false

    private let categories = ["日常用品", "食品", "醫療用品", "交通", "其他"]

    init(ocrResult: OCRResult, onSave: @escaping () -> Void) {
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
                    }
                    DatePicker("消費日期", selection: $receiptDate, displayedComponents: .date)
                }

                Section("分類與備註") {
                    Picker("分類", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
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
            .navigationTitle("確認收據資訊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("儲存") { dismiss(); onSave() }
                        .bold().foregroundStyle(Color.brandTeal)
                        .disabled(storeName.isEmpty && totalAmount.isEmpty)
                }
            }
        }
    }
}

#Preview {
    SpendingView(showProfile: .constant(false), userRole: .family)
}
