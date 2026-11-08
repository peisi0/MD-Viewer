import SwiftUI
import UIKit

/// Renders one parsed block using native SwiftUI views.
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    /// Shared per-document cache; identity is namespaced by `documentID`.
    let cache: InlineTextCache
    let documentID: UUID
    var highlight: String? = nil

    @Environment(\.readerStyle) private var style
    @Environment(\.readerContentWidth) private var contentWidth
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        Group {
            switch block.kind {
            case .heading(let level, let inline, _):
                Text(attributed(inline, font: style.headingFont(level: level), slot: 0))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, level <= 2 ? 26 : 18)
                    .padding(.bottom, 5)
                    .accessibilityAddTraits(.isHeader)

            case .paragraph(let inline):
                Text(attributed(inline, slot: 0))
                    .lineSpacing(style.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 11)

            case .quote(let children):
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(style.accentColor.opacity(0.85))
                        .frame(width: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(children) { child in
                            MarkdownBlockView(block: child,
                                              cache: cache,
                                              documentID: documentID,
                                              highlight: highlight)
                                .id("block-\(child.id)")
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 10)
                .padding(.trailing, 10)
                .background(style.accentColor.opacity(0.075),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 12)

            case .list(let entries):
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            listMarker(for: entry)
                                .frame(minWidth: 22, alignment: .trailing)
                            Text(attributed(entry.inline, slot: entry.id))
                                .lineSpacing(style.lineSpacing * 0.6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, CGFloat(entry.depth) * 20)
                    }
                }
                .padding(.bottom, 12)

        case .code(let language, let code):
            codeBlock(language: language, code: code)

        case .rule:
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.primary.opacity(0.28), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
                .padding(.vertical, 20)

        case .table(let header, let alignments, let rows):
            table(header: header, alignments: alignments, rows: rows)

        case .image(let alt, let src):
            imageBlock(alt: alt, src: src)
            }
        }
    }

    // MARK: - Parts

    /// Builds (or reuses) the attributed text for one text run inside this block.
    private func attributed(_ nodes: [InlineNode],
                            font: Font? = nil,
                            color: Color = .primary,
                            slot: Int) -> AttributedString {
        let key = [
            documentID.uuidString,
            String(block.id),
            String(slot),
            style.cacheKey,
            colorScheme == .dark ? "dark" : "light",
            highlight ?? ""
        ].joined(separator: "|")
        return cache.attributed(key) {
            inlineAttributed(nodes, style: style, font: font, color: color, highlight: highlight)
        }
    }

    @ViewBuilder
    private func listMarker(for entry: ListEntry) -> some View {
        if let checked = entry.checked {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? style.accentColor : Color.secondary)
                .font(.system(size: style.bodySize * 0.92))
        } else if entry.ordered {
            Text("\(entry.number).")
                .font(.system(size: style.bodySize * 0.86, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.8))
                .frame(width: 6, height: 6)
        }
    }

    private func codeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(language?.uppercased() ?? "TEXT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = code
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    withAnimation(.spring(duration: 0.25)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "已复制" : "复制",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider().opacity(0.4)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(style.codeFont)
                    .lineSpacing(4)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(14)
                    .textSelection(.enabled)
            }
            .frame(width: contentWidth, alignment: .leading)
        }
        .background(Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .padding(.vertical, 7)
    }

    private func table(header: [[InlineNode]],
                       alignments: [ColumnAlignment],
                       rows: [[[InlineNode]]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(header, alignments: alignments, rowIndex: -1, isHeader: true)
                Divider().opacity(0.45)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, alignments: alignments, rowIndex: index, isHeader: false)
                        .background(index % 2 == 1 ? Color.primary.opacity(0.035) : Color.clear)
                    if index != rows.count - 1 { Divider().opacity(0.18) }
                }
            }
            .padding(12)
        }
        .frame(width: contentWidth, alignment: .leading)
        .background(Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .padding(.vertical, 8)
    }

    private func tableRow(_ cells: [[InlineNode]],
                          alignments: [ColumnAlignment],
                          rowIndex: Int,
                          isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                let font = isHeader ? style.bodyFont.bold() : style.bodyFont
                let slot = isHeader ? 10_000 + index : 20_000 + rowIndex * 100 + index
                Text(attributed(cells[index], font: font, slot: slot))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 108, alignment: index < alignments.count
                           ? alignments[index].alignment : .leading)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func imageBlock(alt: String, src: String) -> some View {
        Group {
            if let url = URL(string: src),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    case .failure:
                        imagePlaceholder(alt: alt, src: src)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            } else {
                imagePlaceholder(alt: alt, src: src)
            }
        }
        .padding(.vertical, 8)
    }

    private func imagePlaceholder(alt: String, src: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.title2)
                .foregroundStyle(style.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(alt.isEmpty ? "图片" : alt)
                    .font(.subheadline.weight(.medium))
                Text(src)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(style.accentColor.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
