import SwiftUI

struct DocumentsView: View {
    @State private var documents = AppDocument.samples
    @State private var selectedCategory = "全部"
    @State private var showUpload = false

    private let categories = ["全部", "保險", "醫療", "證件", "合約", "其他"]

    var filteredDocuments: [AppDocument] {
        selectedCategory == "全部" ? documents : documents.filter { $0.category == selectedCategory }
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
                        DocumentRow(document: doc)
                            .listRowBackground(Color.white)
                    }
                    .onDelete { indexSet in
                        documents.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.plain)
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
            }
        }
    }
}

// MARK: - Document Row
struct DocumentRow: View {
    let document: AppDocument

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
                    Text(document.category)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(document.categoryColor.opacity(0.12)))
                        .foregroundStyle(document.categoryColor)
                    Text(document.fileSize)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(document.uploadDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button {
                    // Preview/download
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.brandTeal)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Upload Document View
struct UploadDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let onUpload: (AppDocument) -> Void

    @State private var title = ""
    @State private var category = "醫療"
    private let categories = ["保險", "醫療", "證件", "合約", "其他"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Upload area
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.brandTeal)
                    Text("點擊上傳文件")
                        .font(.system(size: 16, weight: .medium))
                    Text("支援 PDF / JPG / PNG（最大 10MB）")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundStyle(Color.brandTeal.opacity(0.4))
                )
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.brandTealLight.opacity(0.3)))
                .padding(.horizontal, 16)
                .onTapGesture { }

                Form {
                    Section("文件標題") {
                        TextField("例：健康檢查報告 2026", text: $title)
                    }
                    Section("分類") {
                        Picker("分類", selection: $category) {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
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
                            title: title.isEmpty ? "未命名文件" : title,
                            category: category,
                            fileSize: "1.2 MB",
                            uploadDate: Date()
                        )
                        onUpload(doc)
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Color.brandTeal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DocumentsView()
    }
}
