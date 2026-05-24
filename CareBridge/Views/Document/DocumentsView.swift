import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct DocumentsView: View {
    @Environment(\.dataService) private var service
    @State private var documents: [AppDocument] = []
    @State private var selectedCategory = "全部"
    @State private var showUpload = false
    // QuickLook 在 iOS 上對 remote presigned URL 不穩定（常常只顯示檔名），
    // 一律先把 processed 檔下載到 caches 再交本機 file:// 給它。
    @State private var previewLocalURL: URL? = nil
    @State private var previewLoadingDocumentID: String?
    @State private var previewError: String?
    @State private var pollingToken = UUID()

    private let pollIntervalNanoseconds: UInt64 = 5_000_000_000
    private let maxPollAttempts = 60

    private let categories = ["全部", "保險", "醫療", "證件", "合約", "其他"]

    // 中文標籤 → API 英文值
    private let categoryAPIMap = [
        "保險": "insurance", "醫療": "medical",
        "證件": "id_document", "合約": "contract", "其他": "other"
    ]

    var filteredDocuments: [AppDocument] {
        guard selectedCategory != "全部" else { return documents }
        let apiValue = categoryAPIMap[selectedCategory] ?? selectedCategory
        return documents.filter { $0.category == apiValue || $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        FilterChip(title: cat, isSelected: selectedCategory == cat) {
                            selectedCategory = cat
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 10)

            // Document list
            if filteredDocuments.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("此分類暫無文件")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(filteredDocuments) { doc in
                        DocumentRow(
                            document: doc,
                            isLoadingPreview: previewLoadingDocumentID == doc.id,
                        ) {
                            Task { await preparePreview(for: doc) }
                        }
                        .listRowBackground(Color.white)
                    }
                    .onDelete(perform: deleteDocuments)
                }
                .listStyle(.plain)
                .quickLookPreview($previewLocalURL)
            }
        }
        .background(Color.brandBackground)
        .navigationTitle("文件管理")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showUpload = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("上傳")
                    }
                    .foregroundStyle(Color.brandTeal)
                    .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showUpload) {
            UploadDocumentView { newDoc in
                documents.insert(newDoc, at: 0)
                schedulePollingIfNeeded()
            }
        }
        .task {
            await refreshDocuments()
        }
        .task(id: pollingToken) {
            await pollDocumentsUntilProcessed()
        }
        .alert("無法載入預覽", isPresented: Binding(
            get: { previewError != nil },
            set: { if !$0 { previewError = nil } }
        )) {
            Button("確定", role: .cancel) { previewError = nil }
        } message: {
            Text(previewError ?? "")
        }
    }

    // MARK: - Preview

    @MainActor
    private func preparePreview(for document: AppDocument) async {
        guard let remoteURL = document.previewURL else { return }
        previewLoadingDocumentID = document.id
        previewError = nil
        defer { previewLoadingDocumentID = nil }

        do {
            previewLocalURL = try await downloadPreviewFile(
                remoteURL: remoteURL,
                documentID: document.id,
            )
        } catch {
            previewError = "Unable to load preview. Please try again."
        }
    }

    private func downloadPreviewFile(remoteURL: URL, documentID: String) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        let ext = Self.previewFileExtension(remoteURL: remoteURL, contentType: contentType)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CareBridgePreviews", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("\(documentID).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func previewFileExtension(remoteURL: URL, contentType: String?) -> String {
        let pathExtension = remoteURL.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "pdf", "txt"].contains(pathExtension) {
            return pathExtension
        }
        switch contentType?.lowercased().split(separator: ";").first.map(String.init) {
        case "image/png":       return "png"
        case "image/jpeg":      return "jpg"
        case "application/pdf": return "pdf"
        case "text/plain":      return "txt"
        default:                return "dat"
        }
    }

    private func deleteDocuments(at indexSet: IndexSet) {
        let deleted = indexSet.map { filteredDocuments[$0] }
        documents.removeAll { doc in deleted.contains { $0.id == doc.id } }
        Task {
            for doc in deleted {
                do {
                    try await service.deleteDocument(id: doc.id)
                } catch {
                    await MainActor.run {
                        documents.insert(doc, at: 0)
                    }
                }
            }
        }
    }

    @MainActor
    private func refreshDocuments(schedulePolling: Bool = true) async {
        do {
            documents = try await service.fetchDocuments()
            if schedulePolling {
                schedulePollingIfNeeded()
            }
        } catch {
            // Keep the existing list visible if a background refresh fails.
        }
    }

    @MainActor
    private func schedulePollingIfNeeded() {
        if documents.contains(where: \.isAwaitingDeidentification) {
            pollingToken = UUID()
        }
    }

    @MainActor
    private func pollDocumentsUntilProcessed() async {
        guard documents.contains(where: \.isAwaitingDeidentification) else { return }

        for _ in 0..<maxPollAttempts {
            do {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            } catch {
                return
            }

            if Task.isCancelled { return }
            await refreshDocuments(schedulePolling: false)

            if !documents.contains(where: \.isAwaitingDeidentification) {
                return
            }
        }
    }
}

// MARK: - Document Row
struct DocumentRow: View {
    let document: AppDocument
    var isLoadingPreview: Bool = false
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(document.categoryColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: document.categoryIcon)
                    .font(.system(size: 20))
                    .foregroundStyle(document.categoryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 15, weight: .medium))
                HStack(spacing: 8) {
                    Text(document.categoryDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(document.categoryColor.opacity(0.12)))
                        .foregroundStyle(document.categoryColor)
                    Text(document.fileSize)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    DocumentDeidStatusBadge(document: document)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(document.uploadDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    onPreview()
                } label: {
                    if isLoadingPreview {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "eye.circle")
                            .foregroundStyle(document.previewURL == nil ? .secondary : Color.brandTeal)
                            .font(.system(size: 20))
                    }
                }
                .buttonStyle(.plain)
                .disabled(document.previewURL == nil || isLoadingPreview)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DocumentDeidStatusBadge: View {
    let document: AppDocument

    var body: some View {
        HStack(spacing: 4) {
            if document.isAwaitingDeidentification {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
        .foregroundStyle(color)
    }

    private var label: String {
        switch document.normalizedDeidStatus {
        case "pending", "processing":
            return "Processing"
        case "needs_review":
            return "Needs review"
        case "failed":
            return "Failed"
        default:
            return "Ready"
        }
    }

    private var iconName: String {
        switch document.normalizedDeidStatus {
        case "needs_review":
            return "exclamationmark.triangle.fill"
        case "failed":
            return "xmark.circle.fill"
        default:
            return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch document.normalizedDeidStatus {
        case "pending", "processing":
            return .orange
        case "needs_review":
            return .yellow
        case "failed":
            return .red
        default:
            return .green
        }
    }
}

// MARK: - Upload Document View
struct UploadDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dataService) private var service
    let onUpload: (AppDocument) -> Void

    @State private var title = ""
    @State private var category = "medical"
    @State private var showFilePicker = false
    @State private var selectedFileName: String? = nil
    @State private var selectedFileSize: String? = nil
    @State private var selectedFileData: Data? = nil
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    // API values as binding values, Chinese for display
    private let categories: [(api: String, display: String)] = [
        ("insurance", "保險"), ("medical", "醫療"),
        ("id_document", "證件"), ("contract", "合約"), ("other", "其他")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Upload area
                Button {
                    showFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        if let fileName = selectedFileName {
                            Image(systemName: "doc.fill.badge.checkmark")
                                .font(.system(size: 48))
                                .foregroundStyle(.green)
                            Text(fileName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("點擊更換")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "arrow.up.doc.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Color.brandTeal)
                            Text("點擊選擇文件")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("支援 PDF / JPG / PNG（最大 10MB）")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(selectedFileName != nil ? Color.green.opacity(0.4) : Color.brandTeal.opacity(0.4))
                    )
                    .background(RoundedRectangle(cornerRadius: 16).fill(
                        selectedFileName != nil ? Color.green.opacity(0.05) : Color.brandTealLight.opacity(0.3)
                    ))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Form {
                    Section("文件標題") {
                        TextField("例：健康檢查報告 2026", text: $title)
                    }
                    Section("分類") {
                        Picker("分類", selection: $category) {
                            ForEach(categories, id: \.api) { cat in
                                Text(cat.display).tag(cat.api)
                            }
                        }
                    }
                }
            }
            .navigationTitle("上傳文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("上傳") {
                        let doc = AppDocument(
                            id: UUID().uuidString,
                            title: title.isEmpty ? (selectedFileName ?? "未命名文件") : title,
                            category: category,
                            fileSize: selectedFileSize ?? "—",
                            uploadDate: Date()
                        )
                        Task { await uploadSelectedDocument() }
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                    .disabled(selectedFileData == nil || isUploading)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.pdf, .image, .png, .jpeg],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        selectedFileName = url.lastPathComponent
                        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            let mb = Double(fileSize) / 1_048_576
                            selectedFileSize = mb < 1 ? "\(Int(mb * 1024)) KB" : String(format: "%.1f MB", mb)
                        }
                        readSelectedFile(url)
                        if title.isEmpty {
                            title = url.deletingPathExtension().lastPathComponent
                        }
                    }
                case .failure(let error):
                    uploadError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func uploadSelectedDocument() async {
        guard let fileData = selectedFileData else { return }
        isUploading = true
        uploadError = nil
        do {
            let document = try await service.uploadDocument(
                title: title.isEmpty ? (selectedFileName ?? "document") : title,
                category: category,
                fileData: fileData
            )
            onUpload(document)
            dismiss()
        } catch {
            uploadError = error.localizedDescription
            isUploading = false
        }
    }

    private func readSelectedFile(_ url: URL) {
        uploadError = nil
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            selectedFileData = try Data(contentsOf: url)
        } catch {
            selectedFileData = nil
            uploadError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
}
