import SwiftUI
import UIKit

private struct ScrollRequest: Equatable {
    let blockID: Int
    let stamp: Int
}

/// A dedicated full-screen reader. It is presented as a sub-screen from the
/// library rather than living in a tab, so there is no bottom tab bar eating
/// vertical space and only one reader view tree exists at a time.
struct ReaderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.readerStyle) private var style

    let document: StoredDocument
    let onBack: () -> Void

    @State private var parsed: MarkdownDocument?
    /// Neither of these is read inside `body`, so scroll/search updates cannot
    /// invalidate the whole document view tree.
    @State private var progress = ReadingProgress()
    @State private var textCache = InlineTextCache()

    @State private var showingTOC = false
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var committedSearch = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var matches: [Int] = []
    @State private var matchIDs: Set<Int> = []
    @State private var matchIndex = 0
    @State private var appearanceExpanded = false
    @State private var showingShare = false
    @State private var scrollRequest: ScrollRequest?
    @State private var stamp = 0
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if let parsed {
                reader(document: document, parsed: parsed)
            } else {
                loadingState
            }
        }
        .task(id: document.id) {
            library.touch(document)
            let fileURL = library.url(for: document)
            let fallbackTitle = document.name
            // Reading, encoding detection and parsing all happen off the main
            // actor; a large .md file no longer freezes the UI on open.
            let load = Task.detached(priority: .userInitiated) { () -> MarkdownDocument in
                let data = (try? Data(contentsOf: fileURL)) ?? Data()
                let text = MarkdownText.decode(data)
                return MarkdownParser().parse(text, fallbackTitle: fallbackTitle)
            }
            let result = await load.value
            guard !Task.isCancelled else { return }

            textCache = InlineTextCache()
            progress.reset()
            parsed = result
            applySearch()
        }
        .onChange(of: searchText) { _, newValue in
            // Debounce so typing does not rebuild attributed text per keystroke.
            searchTask?.cancel()
            searchTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 160_000_000)
                guard !Task.isCancelled else { return }
                committedSearch = newValue
                applySearch()
                if let first = matches.first { requestScroll(to: first) }
            }
        }
    }

    // MARK: - Reader

    private func reader(document: StoredDocument, parsed: MarkdownDocument) -> some View {
        NavigationStack {
            // Pin the whole screen to the proposed width. Without this a wide
            // GFM table expands the cover's ideal width past the device, the
            // cover gets centred, and the left edge (plus its padding) lands
            // off-screen so paragraphs look flush/clipped.
            GeometryReader { outer in
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                documentHeader(document: document, parsed: parsed)

                                ForEach(parsed.blocks) { block in
                                    MarkdownBlockView(
                                        block: block,
                                        cache: textCache,
                                        documentID: parsed.id,
                                        highlight: matchIDs.contains(block.id) ? committedSearch : nil
                                    )
                                    .id("block-\(block.id)")
                                }

                                Spacer(minLength: 24)
                            }
                            .padding(.top, 8)
                            .frame(width: max(1, outer.size.width - 40), alignment: .topLeading)
                            .environment(\.readerContentWidth, max(1, outer.size.width - 40))
                            .textSelection(.enabled)
                        }
                        .padding(.horizontal, 20)
                        // ScrollGeometry is owned by the ScrollView itself, so it
                        // survives lazy recycling of offscreen content views.
                        .onScrollGeometryChange(for: CGFloat.self) { geo in
                            let scrollable = max(1, geo.contentSize.height - geo.containerSize.height)
                            let offset = geo.contentOffset.y + geo.contentInsets.top
                            return min(1, max(0, offset / scrollable))
                        } action: { _, value in
                            progress.setFraction(value)
                        }
                        .onChange(of: scrollRequest) { _, request in
                            guard let request else { return }
                            withAnimation(.easeInOut(duration: 0.42)) {
                                proxy.scrollTo("block-\(request.blockID)", anchor: .top)
                            }
                        }
                    }

                    controlStack
                }
                .frame(width: outer.size.width, height: outer.size.height, alignment: .top)
            }
            .background { GlassBackdrop(intensity: 0.30) }
            .navigationTitle(parsed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("返回", systemImage: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            Task { @MainActor in
                                let text = await library.contentAsync(of: document)
                                UIPasteboard.general.string = text
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            Label("复制 Markdown 原文", systemImage: "doc.on.doc")
                        }
                        Button {
                            showingShare = true
                        } label: {
                            Label("分享原文件", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            requestScroll(to: parsed.blocks.first?.id ?? 0)
                        } label: {
                            Label("回到顶部", systemImage: "arrow.up.to.line")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTOC) {
                outlineSheet(parsed: parsed)
            }
            .sheet(isPresented: $showingShare) {
                ActivityShareView(items: [library.url(for: document) as Any, parsed.title],
                                  isPresented: $showingShare)
                    .presentationDetents([.medium])
                    .presentationBackground(.clear)
            }
            .environment(\.openURL, OpenURLAction { url in
                handle(url, parsed: parsed)
            })
            .onAppear {
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-mdv-appearance") { appearanceExpanded = true }
                if args.contains("-mdv-search") {
                    showingSearch = true
                    searchText = "玻璃"
                    committedSearch = "玻璃"
                    applySearch()
                }
                if args.contains("-mdv-scroll-end") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        requestScroll(to: parsed.blocks.last?.id ?? 0)
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Header

    private func documentHeader(document: StoredDocument, parsed: MarkdownDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "doc.text")
                    .foregroundStyle(style.accentColor)
                Text(document.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(parsed.title)
                .font(.system(size: style.bodySize * 1.7, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                GlassChip(systemImage: "textformat.size", text: "\(parsed.wordCount) 字")
                GlassChip(systemImage: "clock", text: "\(parsed.readingMinutes) 分钟")
                GlassChip(systemImage: "list.bullet", text: "\(parsed.headings.count) 节")
            }

            if !parsed.frontMatter.isEmpty {
                GlassCard(cornerRadius: 18, tint: style.accentColor.opacity(0.08), padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(parsed.frontMatter.prefix(5).enumerated()), id: \.offset) { _, pair in
                            HStack(alignment: .top, spacing: 10) {
                                Text(pair.key)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(style.accentColor)
                                    .frame(width: 72, alignment: .leading)
                                Text(pair.value)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }

            Rectangle()
                .fill(LinearGradient(colors: [style.accentColor.opacity(0.5), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.bottom, 10)
    }

    // MARK: - Bottom control stack

    /// Everything that used to float over the text now lives in one compact
    /// bar pinned to the bottom. The progress line sits at its top edge.
    private var controlStack: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 10) {
                if appearanceExpanded {
                    AppearancePanel {
                        withAnimation(.bouncy) { appearanceExpanded = false }
                    }
                    .glassEffect(
                        .regular.tint(style.accentColor.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
                    .glassEffectID("appearance", in: glassNamespace)
                    .glassEffectTransition(.matchedGeometry)
                }

                if showingSearch {
                    searchBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomBar
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
            .animation(.bouncy, value: showingSearch)
            .animation(.bouncy, value: appearanceExpanded)
        }
        .tint(style.accentColor)
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            // Full-width progress, moved all the way down. Only this view
            // observes ReadingProgress.fraction.
            ReaderProgressBar(progress: progress, expanded: true)
                .padding(.horizontal, 6)

            HStack(spacing: 12) {
                Spacer(minLength: 0)
                controlButton("目录", "list.bullet", id: "toc") {
                    showingTOC = true
                }
                Spacer()
                controlButton("搜索", "magnifyingglass", id: "search") {
                    withAnimation(.bouncy) { showingSearch.toggle() }
                    if !showingSearch { searchText = "" }
                }
                Spacer()
                if !appearanceExpanded {
                    controlButton("排版", "textformat.size", id: "appearance") {
                        withAnimation(.bouncy) { appearanceExpanded = true }
                    }
                    .glassEffectTransition(.matchedGeometry)
                    Spacer()
                }
                controlButton("分享", "square.and.arrow.up", id: "share", prominent: true) {
                    showingShare = true
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
        // A plain colour fill, not a nested glass surface: stacking glass on
        // glass would force an extra compositing pass on every redraw.
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }

    @ViewBuilder
    private func controlButton(_ title: String, _ icon: String, id: String,
                               prominent: Bool = false,
                               action: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: icon)
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .glassEffectID(id, in: glassNamespace)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .glassEffectID(id, in: glassNamespace)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("在文档中搜索", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { jump(1) }

            if !searchText.isEmpty {
                Text(matches.isEmpty ? "0/0" : "\(matchIndex + 1)/\(matches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button { jump(-1) } label: {
                    Image(systemName: "chevron.up").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                Button { jump(1) } label: {
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.bouncy) {
                    showingSearch = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(
            .regular.tint(style.accentColor.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    // MARK: - Outline

    private func outlineSheet(parsed: MarkdownDocument) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if parsed.headings.isEmpty {
                        Text("这篇文档没有标题")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                    ForEach(parsed.headings) { heading in
                        Button {
                            showingTOC = false
                            requestScroll(to: heading.blockID)
                        } label: {
                            HStack {
                                Text(heading.text)
                                    .font(heading.level <= 2 ? .subheadline.weight(.semibold) : .subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                Spacer(minLength: 8)
                                Text("H\(heading.level)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 14)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showingTOC = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Loading state

    private var loadingState: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(intensity: 0.5)
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(style.accentColor)
                    Text("正在解析文档…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("阅读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Label("返回", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Recomputes search hits from the cached per-block plain text.
    private func applySearch() {
        guard let parsed else { return }
        let term = committedSearch
        guard !term.isEmpty else {
            matches = []
            matchIDs = []
            matchIndex = 0
            return
        }
        let found: [Int] = parsed.blocks.compactMap { block in
            guard let text = parsed.blockText[block.id],
                  text.range(of: term, options: .caseInsensitive) != nil else { return nil }
            return block.id
        }
        matches = found
        matchIDs = Set(found)
        matchIndex = 0
    }

    private func requestScroll(to blockID: Int) {
        stamp += 1
        scrollRequest = ScrollRequest(blockID: blockID, stamp: stamp)
    }

    private func jump(_ delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        requestScroll(to: matches[matchIndex])
    }

    private func handle(_ url: URL, parsed: MarkdownDocument) -> OpenURLAction.Result {
        guard url.scheme == "mdviewer" else { return .systemAction }
        let value = (url.lastPathComponent.removingPercentEncoding ?? "")
        if url.host == "anchor" {
            let target = slug(value)
            if let heading = parsed.headings.first(where: { slug($0.text) == target }) {
                requestScroll(to: heading.blockID)
            }
            return .handled
        }
        library.errorMessage = "相对链接：\(value)"
        return .handled
    }

    private func slug(_ string: String) -> String {
        String(string.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })
    }
}
