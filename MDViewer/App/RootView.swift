import SwiftUI

enum AppTab: Int, Hashable {
    case library = 0
    case settings = 1
}

struct RootView: View {
    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.lineSpacing) private var lineSpacing = 7.0
    @AppStorage(Prefs.accent) private var accent = "indigo"
    @AppStorage(Prefs.theme) private var theme = 0

    @State private var library = LibraryStore()
    @State private var tab: AppTab = .library
    /// The reader is a separate full-screen sub-screen, not a tab. Only one
    /// reader view tree exists, and only while a document is actually open.
    @State private var readerDocument: StoredDocument?
    @State private var importError: String?
    @State private var showingImportError = false

    private var style: ReaderStyle {
        ReaderStyle(fontSize: fontSize, lineSpacing: lineSpacing,
                    accentName: accent, theme: theme)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("资料库", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryView(onOpen: openDocument)
            }

            Tab("设置", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(style.accentColor)
        .environment(library)
        .environment(\.readerStyle, style)
        .preferredColorScheme(style.preferredScheme)
        .fullScreenCover(item: $readerDocument) { document in
            // A fullScreenCover gets its own hosting controller, and SwiftUI
            // does not carry an @Observable environment value across it.
            // Inject explicitly or the reader traps on first render.
            ReaderView(document: document, onBack: { readerDocument = nil })
                .environment(library)
                .environment(\.readerStyle, style)
                .tint(style.accentColor)
                .preferredColorScheme(style.preferredScheme)
        }
        .onOpenURL { url in handleIncoming(url) }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-mdv-settings") { tab = .settings }
            if args.contains("-mdv-no-samples") { library.removeAllSamples() }
            if args.contains("-mdv-open-first"),
               readerDocument == nil, let first = library.documents.first {
                openDocument(first)
            }
            if args.contains("-mdv-import-test") {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let test = "# 导入测试\n\n这是通过「扫描文档目录」导入的 README.md。\n\n- 表格、代码块与中文都应正常显示\n"
                try? test.write(to: docs.appendingPathComponent("README.md"),
                                atomically: true, encoding: .utf8)
                Task { @MainActor in
                    _ = await library.scanDocumentsDirectory()
                    library.errorMessage = nil
                    if let doc = library.documents.first(where: { $0.name == "README.md" }) {
                        openDocument(doc)
                    }
                }
            }
            #endif
        }
        .alert("无法打开文件", isPresented: $showingImportError) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func openDocument(_ document: StoredDocument) {
        readerDocument = document
    }

    /// Handles "Open in MD Viewer" from the Files app / share sheet.
    private func handleIncoming(_ url: URL) {
        guard url.isFileURL else { return }
        Task { @MainActor in
            if let document = await library.importFile(url) {
                openDocument(document)
            } else {
                importError = library.errorMessage ?? "无法读取 \(url.lastPathComponent)"
                library.errorMessage = nil
                showingImportError = true
            }
        }
    }
}
