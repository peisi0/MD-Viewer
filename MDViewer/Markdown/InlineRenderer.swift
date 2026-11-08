import Foundation
import SwiftUI

/// Stage 2 of the rendering pipeline: `[InlineNode]` → `AttributedString`.
/// Using AttributedString (instead of a WebView) gives us text selection,
/// Dynamic Type, tappable links and native rendering for free.
func inlineAttributed(
    _ nodes: [InlineNode],
    style: ReaderStyle,
    font: Font? = nil,
    color: Color = .primary,
    highlight: String? = nil
) -> AttributedString {
    let resolved = font ?? style.bodyFont
    var base = AttributeContainer()
    base.font = resolved
    base.foregroundColor = color
    return render(nodes, base, resolved, style, highlight)
}

private func render(
    _ nodes: [InlineNode],
    _ attrs: AttributeContainer,
    _ font: Font,
    _ style: ReaderStyle,
    _ highlight: String?
) -> AttributedString {
    var result = AttributedString()

    for node in nodes {
        switch node {
        case .text(let string):
            appendText(string, attrs, highlight, into: &result)

        case .strong(let children):
            var a = attrs
            a.font = font.bold()
            result.append(render(children, a, font, style, highlight))

        case .emphasis(let children):
            var a = attrs
            a.font = font.italic()
            result.append(render(children, a, font, style, highlight))

        case .strikethrough(let children):
            var a = attrs
            a.strikethroughStyle = .single
            a.foregroundColor = .secondary
            result.append(render(children, a, font, style, highlight))

        case .code(let string):
            var a = attrs
            a.font = style.monoFont
            a.foregroundColor = style.accentColor
            a.backgroundColor = Color.primary.opacity(0.08)
            result.append(AttributedString(string, attributes: a))

        case .link(let children, let destination):
            var a = attrs
            a.foregroundColor = style.accentColor
            a.underlineStyle = .single
            a.link = MarkdownLink.url(for: destination)
            result.append(render(children, a, font, style, highlight))

        case .image(let alt, let src):
            var a = attrs
            a.foregroundColor = .secondary
            a.font = style.captionFont
            result.append(AttributedString("▧ \(alt.isEmpty ? src : alt)", attributes: a))

        case .hardBreak:
            result.append(AttributedString("\n", attributes: attrs))
        }
    }
    return result
}

private func appendText(
    _ string: String,
    _ attrs: AttributeContainer,
    _ highlight: String?,
    into output: inout AttributedString
) {
    guard let term = highlight, !term.isEmpty else {
        output.append(AttributedString(string, attributes: attrs))
        return
    }

    var remaining = Substring(string)
    while !remaining.isEmpty {
        guard let match = remaining.range(of: term, options: .caseInsensitive) else {
            output.append(AttributedString(String(remaining), attributes: attrs))
            return
        }
        if match.lowerBound > remaining.startIndex {
            output.append(AttributedString(String(remaining[..<match.lowerBound]), attributes: attrs))
        }
        var marked = attrs
        marked.backgroundColor = Color.yellow.opacity(0.62)
        marked.foregroundColor = Color.primary
        output.append(AttributedString(String(remaining[match]), attributes: marked))
        remaining = remaining[match.upperBound...]
    }
}

enum MarkdownLink {
    /// Absolute links pass through; anchors and relative files use an internal
    /// scheme handled by the reader's OpenURLAction.
    static func url(for destination: String) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "tel", "sms", "facetime"].contains(scheme) {
            return url
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        if trimmed.hasPrefix("#") {
            return URL(string: "mdviewer://anchor/\(encoded)")
        }
        return URL(string: "mdviewer://open/\(encoded)")
    }
}
