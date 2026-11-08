import Foundation
import SwiftUI

// MARK: - Inline syntax tree

enum InlineNode {
    case text(String)
    case strong([InlineNode])
    case emphasis([InlineNode])
    case strikethrough([InlineNode])
    case code(String)
    case link([InlineNode], String)
    case image(alt: String, src: String)
    case hardBreak
}

func inlinePlainText(_ nodes: [InlineNode]) -> String {
    var out = ""
    for node in nodes {
        switch node {
        case .text(let s): out += s
        case .strong(let c), .emphasis(let c), .strikethrough(let c): out += inlinePlainText(c)
        case .code(let s): out += s
        case .link(let c, _): out += inlinePlainText(c)
        case .image(let alt, let src): out += alt.isEmpty ? src : alt
        case .hardBreak: out += "\n"
        }
    }
    return out
}

// MARK: - Block syntax tree

enum ColumnAlignment {
    case leading, center, trailing

    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct ListEntry: Identifiable {
    let id: Int
    let depth: Int
    let ordered: Bool
    let number: Int
    let checked: Bool?
    let inline: [InlineNode]
}

enum BlockKind {
    case heading(level: Int, inline: [InlineNode], plain: String)
    case paragraph([InlineNode])
    case quote([MarkdownBlock])
    case list(entries: [ListEntry])
    case code(language: String?, code: String)
    case rule
    case table(header: [[InlineNode]], alignments: [ColumnAlignment], rows: [[[InlineNode]]])
    case image(alt: String, src: String)
}

struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: BlockKind
}

struct HeadingItem: Identifiable {
    let id: Int
    let level: Int
    let text: String
    let blockID: Int
}

struct MarkdownDocument: @unchecked Sendable {
    /// Identity of this parse result. Used to namespace the attributed-text cache.
    var id: UUID = UUID()
    var title: String = ""
    var frontMatter: [(key: String, value: String)] = []
    var blocks: [MarkdownBlock] = []
    var headings: [HeadingItem] = []
    var plainText: String = ""
    /// Plain text keyed by block id (includes nested quote children), so search
    /// never has to walk the inline syntax tree again.
    var blockText: [Int: String] = [:]
    var wordCount: Int = 0
    var readingMinutes: Int = 1
}

final class BlockIDGenerator {
    private var current = 0
    func next() -> Int {
        current += 1
        return current
    }
}

// MARK: - Plain-text helpers (search, word count)

func plainText(of block: MarkdownBlock) -> String {
    switch block.kind {
    case .heading(_, _, let plain):
        return plain
    case .paragraph(let nodes):
        return inlinePlainText(nodes)
    case .quote(let children):
        return children.map(plainText(of:)).joined(separator: " ")
    case .list(let entries):
        return entries.map { inlinePlainText($0.inline) }.joined(separator: " ")
    case .code(_, let code):
        return code
    case .rule:
        return ""
    case .table(let header, _, let rows):
        return (header + rows.flatMap { $0 }).map(inlinePlainText).joined(separator: " ")
    case .image(let alt, let src):
        return alt.isEmpty ? src : alt
    }
}

func collectHeadings(_ blocks: [MarkdownBlock], into result: inout [HeadingItem], generator: BlockIDGenerator) {
    for block in blocks {
        switch block.kind {
        case .heading(let level, _, let plain):
            result.append(HeadingItem(id: generator.next(), level: level, text: plain, blockID: block.id))
        case .quote(let children):
            collectHeadings(children, into: &result, generator: generator)
        default:
            break
        }
    }
}

/// Precomputes searchable plain text for every block, including blocks nested
/// inside quotes. Computed once per parse instead of on every search keystroke.
func blockTextMap(_ blocks: [MarkdownBlock]) -> [Int: String] {
    var map: [Int: String] = [:]
    func walk(_ list: [MarkdownBlock]) {
        for block in list {
            map[block.id] = plainText(of: block)
            if case .quote(let children) = block.kind { walk(children) }
        }
    }
    walk(blocks)
    return map
}

/// Single-pass word count: CJK characters count individually, ASCII runs count
/// as words. Avoids allocating an array of every whitespace-separated token.
func countWords(_ text: String) -> Int {
    var cjk = 0
    var latin = 0
    var inASCIIWord = false
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0x3040...0x30FF).contains(v) {
            cjk += 1
            inASCIIWord = false
            continue
        }
        let isAlnum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
        if isAlnum {
            if !inASCIIWord { latin += 1; inASCIIWord = true }
        } else {
            inASCIIWord = false
        }
    }
    return cjk + latin
}
