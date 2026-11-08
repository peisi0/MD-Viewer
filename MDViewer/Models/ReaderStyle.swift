import SwiftUI
import UIKit

struct AccentOption: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
}

let accentOptions: [AccentOption] = [
    .init(id: "indigo",   name: "靛蓝", color: Color(red: 0.40, green: 0.42, blue: 0.94)),
    .init(id: "cyan",     name: "青蓝", color: Color(red: 0.13, green: 0.70, blue: 0.86)),
    .init(id: "pink",     name: "粉霞", color: Color(red: 0.94, green: 0.38, blue: 0.61)),
    .init(id: "orange",   name: "暖橙", color: Color(red: 0.97, green: 0.56, blue: 0.26)),
    .init(id: "mint",     name: "薄荷", color: Color(red: 0.20, green: 0.76, blue: 0.58)),
    .init(id: "graphite", name: "石墨", color: Color(red: 0.40, green: 0.44, blue: 0.52))
]

enum Prefs {
    static let fontSize = "mdv.fontSize"
    static let lineSpacing = "mdv.lineSpacing"
    static let accent = "mdv.accent"
    static let theme = "mdv.theme"
    static let animatedBackdrop = "mdv.animatedBackdrop"
}

/// Typography + colour settings shared through the SwiftUI environment.
/// Sizes pass through `UIFontMetrics` so Dynamic Type still works with custom fonts.
struct ReaderStyle: Equatable {
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var accentName: String
    var theme: Int

    init(fontSize: CGFloat = 17, lineSpacing: CGFloat = 7,
         accentName: String = "indigo", theme: Int = 0) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.accentName = accentName
        self.theme = theme
    }

    var accentColor: Color {
        accentOptions.first { $0.id == accentName }?.color ?? accentOptions[0].color
    }

    /// Stable identity for the attributed-text cache.
    var cacheKey: String {
        "\(Int(fontSize))/\(Int(lineSpacing))/\(accentName)/\(theme)"
    }

    var preferredScheme: ColorScheme? {
        switch theme {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        min(base * 1.9, UIFontMetrics(forTextStyle: .body).scaledValue(for: base))
    }

    var bodySize: CGFloat { scaled(fontSize) }
    var bodyFont: Font { .system(size: bodySize, weight: .regular) }
    var monoFont: Font { .system(size: scaled(fontSize * 0.86), weight: .regular, design: .monospaced) }
    var codeFont: Font { .system(size: scaled(fontSize * 0.82), weight: .regular, design: .monospaced) }
    var captionFont: Font { .system(size: scaled(fontSize * 0.70), weight: .medium) }

    func headingFont(level: Int) -> Font {
        let factors: [CGFloat] = [1.95, 1.58, 1.34, 1.18, 1.08, 1.0]
        let index = max(0, min(5, level - 1))
        return .system(size: scaled(fontSize * factors[index]), weight: .bold)
    }
}

private struct ReaderStyleKey: EnvironmentKey {
    static let defaultValue = ReaderStyle()
}

extension EnvironmentValues {
    var readerStyle: ReaderStyle {
        get { self[ReaderStyleKey.self] }
        set { self[ReaderStyleKey.self] = newValue }
    }
}
