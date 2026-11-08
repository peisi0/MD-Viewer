import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.readerStyle) private var style
    @Environment(\.openURL) private var openURL

    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.lineSpacing) private var lineSpacing = 7.0
    @AppStorage(Prefs.accent) private var accent = "indigo"
    @AppStorage(Prefs.theme) private var theme = 0
    @AppStorage(Prefs.animatedBackdrop) private var animatedBackdrop = false

    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackdrop(intensity: 0.85)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        appHeader
                        appearanceSection
                        librarySection
                        formatsSection
                        aboutSection
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
            }
            .navigationTitle("设置")
            .tint(style.accentColor)
            .alert("清空已导入文档？", isPresented: $showingClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { library.clearImported() }
            } message: {
                Text("内置的示例文档会保留。这个操作只会移除你导入的文件。")
            }
        }
    }

    // MARK: - Sections

    private var appHeader: some View {
        GlassCard(cornerRadius: 28, tint: style.accentColor.opacity(0.10)) {
            HStack(spacing: 16) {
                AppIconBadge(size: 82)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MD Viewer")
                        .font(.title2.weight(.bold))
                    Text("版本 1.1 · Build 2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("iOS 26+ · Liquid Glass")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(style.accentColor)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var appearanceSection: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("阅读外观", icon: "textformat.size")

                StyleSlider(title: "字号", value: $fontSize, range: 14...24) {
                    EmptyView()
                } trailing: {
                    EmptyView()
                }
                StyleSlider(title: "行距", value: $lineSpacing, range: 2...18) {
                    EmptyView()
                } trailing: {
                    EmptyView()
                }

                Toggle(isOn: $animatedBackdrop) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("动态背景")
                            .font(.subheadline)
                        Text("渐变缓慢流动会增加耗电与发热，默认关闭。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(style.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Text("外观").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Array(["跟随系统", "浅色", "深色"].enumerated()), id: \.offset) { index, title in
                            if theme == index {
                                Button { withAnimation { theme = index } } label: { themeLabel(title) }
                                    .buttonStyle(.glassProminent)
                            } else {
                                Button { withAnimation { theme = index } } label: { themeLabel(title) }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("强调色").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(accentOptions) { option in
                            Button {
                                withAnimation { accent = option.id }
                            } label: {
                                ZStack {
                                    Circle().fill(option.color).frame(width: 30, height: 30)
                                    if accent == option.id {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                        }
                        Spacer(minLength: 0)
                    }
                }

                Text("Ag 示例文字：玻璃会折射背后的颜色，文字始终清晰。")
                    .font(.system(size: fontSize))
                    .lineSpacing(lineSpacing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var librarySection: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("资料库", icon: "books.vertical")

                HStack(spacing: 10) {
                    GlassChip(systemImage: "doc.text", text: "\(library.documents.count) 篇")
                    GlassChip(systemImage: "tray.and.arrow.down", text: "\(library.importedCount) 已导入")
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button {
                        library.seedSamples()
                    } label: {
                        Label("恢复示例", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)

                    Button {
                        showingClearConfirm = true
                    } label: {
                        Label("清空导入", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var formatsSection: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("支持格式", icon: "doc.badge.gearshape")
                Text(".md  .markdown  .mdown  .mkd  .mkdn  .mdtxt  .txt")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("编码自动识别：UTF-8 / UTF-16 / GB18030。支持从「文件」App 直接打开，也支持通过 Finder 文件共享放入 Documents 目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var aboutSection: some View {
        GlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("关于", icon: "info.circle")
                Text("使用 SwiftUI 原生渲染 Markdown，不依赖 WebView。界面基于 iOS 26 的 Glass、GlassEffectContainer 与 glassEffectID 构建。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    if let url = URL(string: "https://www.markdownguide.org/basic-syntax/") {
                        openURL(url)
                    }
                } label: {
                    Label("Markdown 语法指南", systemImage: "link")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        Text("Made with SwiftUI · Xcode 27 · iOS 26 SDK")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    private func themeLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
    }
}
