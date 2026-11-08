import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.readerStyle) private var style

    let onOpen: (StoredDocument) -> Void

    @State private var picker = DocumentPickerPresenter()
    @State private var scanning = false
    @State private var notice: String?
    @State private var showingNotice = false
    @State private var pendingDelete: StoredDocument?
    @State private var showingDeleteConfirm = false
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
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("资料库")
            .searchable(text: $searchText, prompt: "搜索文档名或内容")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            picker.present()
                        } label: {
                            Label("从「文件」导入", systemImage: "folder")
                        }
                        Button {
                            scanDocuments()
                        } label: {
                            Label("扫描文档目录", systemImage: "doc.viewfinder")
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
            .alert("导入提示", isPresented: $showingNotice) {
                Button("好", role: .cancel) { notice = nil }
            } message: {
                Text(notice ?? "")
            }
            .confirmationDialog("删除文档", isPresented: $showingDeleteConfirm,
                                presenting: pendingDelete) { document in
                Button("删除", role: .destructive) {
                    library.delete(document)
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: { document in
                Text(document.isSample
                     ? "《\(document.name)》是内置示例，只会从资料库移除，可在「设置 → 恢复示例」找回。"
                     : "《\(document.name)》及其文件会一并删除。")
            }
            .onAppear {
                picker.onPick = { urls in handlePicked(urls) }
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-mdv-picker") {
                    DispatchQueue.main.async { picker.present() }
                }
                if ProcessInfo.processInfo.arguments.contains("-mdv-pick-sim") {
                    let docs = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask)[0]
                    let file = docs.appendingPathComponent("PickerTest.md")
                    try? "# 选择器导入测试\n\n模拟 asCopy 返回的本地文件 URL 导入成功。\n"
                        .write(to: file, atomically: true, encoding: .utf8)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        picker.onPick?([file])
                    }
                }
                #endif
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

                Text("导入 .md 文件，或把文件放进 App 的文档目录后点「扫描文档目录」——后者不依赖文件选择器，在侧载环境里更可靠。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        picker.present()
                    } label: {
                        Label("导入文件", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        scanDocuments()
                    } label: {
                        Label(scanning ? "扫描中…" : "扫描目录", systemImage: "doc.viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.glass)
                    .disabled(scanning)
                }
            }
        }
        .tint(style.accentColor)
    }

    private func documentCard(_ document: StoredDocument) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onOpen(document)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: document.isSample ? "sparkles.rectangle.stack" : "doc.text.fill")
                            .font(.title2)
                            .foregroundStyle(style.accentColor)
                        Spacer()
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
                        if document.isSample {
                            Text("示例")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
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

            // Visible on every card (including bundled samples) so samples can
            // be removed without hunting through a long-press menu.
            Button {
                pendingDelete = document
                showingDeleteConfirm = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("删除 \(document.name)")
        }
        .contextMenu {
            Button {
                onOpen(document)
            } label: {
                Label("打开", systemImage: "book")
            }
            Button(role: .destructive) {
                pendingDelete = document
                showingDeleteConfirm = true
            } label: {
                Label(document.isSample ? "移除示例" : "从资料库删除", systemImage: "trash")
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
                Text("导入一个 .md 文件，或从剪贴板新建一篇。内置示例可在「设置」里恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        picker.present()
                    } label: {
                        Label("导入 Markdown", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        scanDocuments()
                    } label: {
                        Label("扫描目录", systemImage: "doc.viewfinder")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Import actions

    private func handlePicked(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            var successes: [StoredDocument] = []
            var failures: [String] = []
            for url in urls {
                if let document = await library.importFile(url) {
                    successes.append(document)
                } else {
                    failures.append(library.errorMessage ?? "无法导入 \(url.lastPathComponent)")
                }
                library.errorMessage = nil
            }
            if failures.isEmpty, let last = successes.last {
                onOpen(last)
            } else {
                var message = successes.isEmpty ? "" : "已导入 \(successes.count) 篇。\n"
                message += failures.joined(separator: "\n")
                notice = message
                showingNotice = true
            }
        }
    }

    private func scanDocuments() {
        guard !scanning else { return }
        scanning = true
        Task { @MainActor in
            let count = await library.scanDocumentsDirectory()
            let error = library.errorMessage
            library.errorMessage = nil
            scanning = false
            var message: String
            if count > 0 {
                message = "从文档目录导入了 \(count) 篇 Markdown。"
            } else {
                message = "文档目录里没有新的 Markdown 文件。把 .md 放进「文件」App 的 MD Viewer 目录（或 Documents/Inbox）后再扫描一次即可。"
                if let error { message += "\n\n\(error)" }
            }
            notice = message
            showingNotice = true
        }
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            notice = "剪贴板里没有文本内容"
            showingNotice = true
            return
        }
        let name = "剪贴板 \(Date().formatted(.dateTime.month().day().hour().minute())).md"
        Task { @MainActor in
            if let document = await library.importDroppedText(text, named: name) {
                onOpen(document)
            } else {
                notice = library.errorMessage ?? "保存失败"
                library.errorMessage = nil
                showingNotice = true
            }
        }
    }
}
