import SwiftUI

enum AppTab: Int, Hashable {
    case library = 0
    case reader = 1
    case settings = 2
}

struct RootView: View {
    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.lineSpacing) private var lineSpacing = 7.0
    @AppStorage(Prefs.accent) private var accent = "indigo"
    @AppStorage(Prefs.theme) private var theme = 0

    @State private var library = LibraryStore()
    @State private var tab: AppTab = .library
    @State private var activeDocument: StoredDocument?
    @State private var importError: String?

    private var style: ReaderStyle {
        ReaderStyle(fontSize: fontSize, lineSpacing: lineSpacing,
                    accentName: accent, theme: theme)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("资料库", systemImage: "books.vertical.fill", value: AppTab.library) {
                LibraryView(onOpen: openDocument, onGoReader: { tab = .reader })
            }

            Tab("阅读", systemImage: "doc.text.fill", value: AppTab.reader) {
                ReaderView(document: activeDocument, onGoLibrary: { tab = .library })
            }

            Tab("设置", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(style.accentColor)
        .environment(library)
        .environment(\.readerStyle, style)
        .preferredColorScheme(style.preferredScheme)
        .onOpenURL { url in handleIncoming(url) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-mdv-open-first"),
               activeDocument == nil, let first = library.documents.first {
                openDocument(first)
            }
            if ProcessInfo.processInfo.arguments.contains("-mdv-settings") { tab = .settings }
            #endif
        }
        .alert("无法打开文件", isPresented: Binding(
            get: { importError != nil },
            set: { presented in if !presented { importError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func openDocument(_ document: StoredDocument) {
        activeDocument = document
        withAnimation(.bouncy) { tab = .reader }
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
            }
        }
    }
}
