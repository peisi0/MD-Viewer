import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.readerStyle) private var style

    let onOpen: (StoredDocument) -> Void
    let onGoReader: () -> Void

    @State private var showingImporter = false
    @State private var searchText = ""

    private var filtered: [StoredDocument] {
        guard !searchText.isEmpty else { return library.documents }
        return library.documents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.preview.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroCard

                        if filtered.isEmpty {
                            emptyCard
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filtered) { document in
                                    documentCard(document)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("资料库")
            .searchable(text: $searchText, prompt: "搜索文档名或内容")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("从「文件」导入", systemImage: "folder")
                        }
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("从剪贴板新建", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: UTType.importableTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { @MainActor in
                        var last: StoredDocument?
                        for url in urls { last = await library.importFile(url) ?? last }
                        if let last { onOpen(last) }
                    }
                case .failure(let error):
                    library.errorMessage = error.localizedDescription
                }
            }
            .alert("提示", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { presented in if !presented { library.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var heroCard: some View {
        GlassCard(cornerRadius: 28, tint: style.accentColor.opacity(0.10)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    AppIconBadge(size: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MD Viewer")
                            .font(.title2.weight(.bold))
                        Text("Liquid Glass · Markdown 阅读器")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    GlassChip(systemImage: "books.vertical", text: "\(library.documents.count) 篇文档")
                    GlassChip(systemImage: "tray.and.arrow.down", text: "\(library.importedCount) 已导入")
                    Spacer(minLength: 0)
                }

                Text("导入 .md 文件，或在「文件」App 里用「共享 → MD Viewer」打开。支持 GFM 表格、任务列表、代码块与 YAML front matter。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("导入文件", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        onGoReader()
                    } label: {
                        Label("继续阅读", systemImage: "book")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .tint(style.accentColor)
    }

    private func documentCard(_ document: StoredDocument) -> some View {
        Button {
            onOpen(document)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: document.isSample ? "sparkles.rectangle.stack" : "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(style.accentColor)
                    Spacer()
                    if document.isSample {
                        Text("示例")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                }

                Text(document.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Text(document.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Divider().opacity(0.4)

                HStack(spacing: 6) {
                    Image(systemName: "textformat.size").imageScale(.small)
                    Text("\(document.wordCount) 字")
                    Spacer(minLength: 0)
                    Text((document.lastOpenedAt ?? document.addedAt)
                        .formatted(.dateTime.month().day()))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(style.accentColor.opacity(0.07)).interactive(),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .contextMenu {
            Button {
                onOpen(document)
            } label: {
                Label("打开", systemImage: "book")
            }
            if !document.isSample {
                Button(role: .destructive) {
                    library.delete(document)
                } label: {
                    Label("从资料库移除", systemImage: "trash")
                }
            }
        }
    }

    private var emptyCard: some View {
        GlassCard(cornerRadius: 26) {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundStyle(style.accentColor)
                Text(searchText.isEmpty ? "资料库是空的" : "没有找到匹配的文档")
                    .font(.headline)
                Text("试试导入一个 .md 文件，或者从剪贴板新建一篇。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showingImporter = true
                } label: {
                    Label("导入 Markdown", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            library.errorMessage = "剪贴板里没有文本内容"
            return
        }
        let name = "剪贴板 \(Date().formatted(.dateTime.month().day().hour().minute())).md"
        Task { @MainActor in
            if let document = await library.importDroppedText(text, named: name) {
                onOpen(document)
            }
        }
    }
}
