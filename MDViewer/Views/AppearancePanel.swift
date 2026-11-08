import SwiftUI

/// Expandable glass panel shown from the reader's bottom toolbar.
/// Writes straight to the same @AppStorage keys the root view observes,
/// so every screen updates instantly.
struct AppearancePanel: View {
    let onClose: () -> Void

    @AppStorage(Prefs.fontSize) private var fontSize = 17.0
    @AppStorage(Prefs.lineSpacing) private var lineSpacing = 7.0
    @AppStorage(Prefs.accent) private var accent = "indigo"
    @AppStorage(Prefs.theme) private var theme = 0
    @Environment(\.readerStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("排版", systemImage: "textformat.size")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            StyleSlider(title: "字号", value: $fontSize, range: 14...24)
            StyleSlider(title: "行距", value: $lineSpacing, range: 2...18)

            VStack(alignment: .leading, spacing: 8) {
                Text("外观").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Array(["跟随系统", "浅色", "深色"].enumerated()), id: \.offset) { index, title in
                        if theme == index {
                            Button { withAnimation(.bouncy) { theme = index } } label: {
                                themeLabel(title)
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button { withAnimation(.bouncy) { theme = index } } label: {
                                themeLabel(title)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("强调色").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(accentOptions) { option in
                        Button {
                            withAnimation(.bouncy) { accent = option.id }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 27, height: 27)
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
                }
            }

            Text("Ag 文字始终清晰可读")
                .font(.system(size: fontSize))
                .lineSpacing(lineSpacing)
                .foregroundStyle(.primary)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 292)
        .tint(style.accentColor)
    }

    private func themeLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
    }
}
