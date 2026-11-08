import Foundation

/// A small, dependency-free inline Markdown tokenizer.
/// Produces `[InlineNode]` which is later folded into an `AttributedString`.
struct InlineParser {
    private let chars: [Character]
    private var pos = 0

    init(_ string: String) {
        chars = Array(string)
    }

    mutating func parse() -> [InlineNode] {
        var nodes: [InlineNode] = []
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                nodes.append(.text(buffer))
                buffer = ""
            }
        }

        while pos < chars.count {
            let c = chars[pos]

            // Escapes
            if c == "\\", pos + 1 < chars.count {
                buffer.append(chars[pos + 1])
                pos += 2
                continue
            }

            // Soft / hard line breaks
            if c == "\n" {
                if buffer.hasSuffix("  ") {
                    buffer.removeLast(2)
                    flush()
                    nodes.append(.hardBreak)
                } else {
                    buffer.append(" ")
                }
                pos += 1
                continue
            }

            // Bare URL
            if (c == "h"), has("http://", at: pos) || has("https://", at: pos),
               pos == 0 || !isAlnum(chars[pos - 1]) {
                if let (url, end) = bareURL(at: pos) {
                    flush()
                    nodes.append(.link([.text(url)], url))
                    pos = end
                    continue
                }
            }

            // Image: ![alt](src)
            if c == "!", has("![", at: pos), let link = parseLink(at: pos + 1) {
                flush()
                nodes.append(.image(alt: inlinePlainText(link.children), src: link.url))
                pos = link.end
                continue
            }

            // Link: [text](url)
            if c == "[", let link = parseLink(at: pos) {
                flush()
                nodes.append(.link(link.children, link.url))
                pos = link.end
                continue
            }

            // Autolink: <https://example.com>
            if c == "<", let auto = parseAutolink(at: pos) {
                flush()
                nodes.append(.link([.text(auto.url)], auto.url))
                pos = auto.end
                continue
            }

            // Code span
            if c == "`", let span = parseCodeSpan(at: pos) {
                flush()
                nodes.append(.code(span.code))
                pos = span.end
                continue
            }

            // Strikethrough
            if has("~~", at: pos), let end = closingRun("~", count: 2, from: pos + 2) {
                flush()
                let inner = parseFragment(pos + 2..<end)
                nodes.append(.strikethrough(inner))
                pos = end + 2
                continue
            }

            // Bold + italic: ***text*** / ___text___
            if (c == "*" || c == "_"), has(String(repeating: c, count: 3), at: pos),
               let end = closingRun(c, count: 3, from: pos + 3) {
                flush()
                let inner = parseFragment(pos + 3..<end)
                nodes.append(.strong([.emphasis(inner)]))
                pos = end + 3
                continue
            }

            // Bold
            if (c == "*" || c == "_"), has(String(repeating: c, count: 2), at: pos),
               boundaryAllowsOpen(c, at: pos),
               let end = closingRun(c, count: 2, from: pos + 2) {
                flush()
                nodes.append(.strong(parseFragment(pos + 2..<end)))
                pos = end + 2
                continue
            }

            // Italic
            if (c == "*" || c == "_"), boundaryAllowsOpen(c, at: pos),
               let end = closingRun(c, count: 1, from: pos + 1) {
                flush()
                nodes.append(.emphasis(parseFragment(pos + 1..<end)))
                pos = end + 1
                continue
            }

            buffer.append(c)
            pos += 1
        }

        flush()
        return nodes
    }

    // MARK: - Helpers

    private func parseFragment(_ range: Range<Int>) -> [InlineNode] {
        var parser = InlineParser(String(chars[range]))
        return parser.parse()
    }

    private func has(_ literal: String, at index: Int) -> Bool {
        let target = Array(literal)
        guard index >= 0, index + target.count <= chars.count else { return false }
        for (offset, ch) in target.enumerated() where chars[index + offset] != ch {
            return false
        }
        return true
    }

    private func isAlnum(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }

    private func boundaryAllowsOpen(_ c: Character, at index: Int) -> Bool {
        let next = index + 1 < chars.count ? chars[index + 1] : " "
        guard !next.isWhitespace else { return false }
        if c == "_" {
            let prev = index > 0 ? chars[index - 1] : " "
            return !isAlnum(prev)
        }
        return true
    }

    private func closingRun(_ c: Character, count: Int, from start: Int) -> Int? {
        let literal = String(repeating: c, count: count)
        var i = start
        while i + count <= chars.count {
            if i > 0, chars[i - 1] == "\\" {
                i += 1
                continue
            }
            if has(literal, at: i) {
                let prev = i > 0 ? chars[i - 1] : " "
                guard !prev.isWhitespace else { i += 1; continue }
                if c == "_" {
                    let next = i + count < chars.count ? chars[i + count] : " "
                    if isAlnum(next) { i += 1; continue }
                }
                // Make sure a longer run isn't being split (e.g. *** inside **)
                return i
            }
            i += 1
        }
        return nil
    }

    private func parseCodeSpan(at start: Int) -> (code: String, end: Int)? {
        var n = 0
        while start + n < chars.count, chars[start + n] == "`" { n += 1 }
        var i = start + n
        while i < chars.count {
            if chars[i] == "`" {
                var m = 0
                while i + m < chars.count, chars[i + m] == "`" { m += 1 }
                if m == n {
                    var code = String(chars[start + n..<i]).replacingOccurrences(of: "\n", with: " ")
                    if code.hasPrefix(" "), code.hasSuffix(" "), code.count > 2 {
                        code = String(code.dropFirst().dropLast())
                    }
                    return (code, i + m)
                }
                i += m
            } else {
                i += 1
            }
        }
        return nil
    }

    private func parseLink(at start: Int) -> (children: [InlineNode], url: String, end: Int)? {
        guard has("[", at: start) else { return nil }
        var depth = 1
        var j = start + 1
        while j < chars.count, depth > 0 {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "[" { depth += 1 }
            if chars[j] == "]" { depth -= 1 }
            if depth == 0 { break }
            j += 1
        }
        guard j < chars.count, chars[j] == "]", j + 1 < chars.count, chars[j + 1] == "(" else { return nil }

        var paren = 1
        var k = j + 2
        while k < chars.count, paren > 0 {
            if chars[k] == "\\" { k += 2; continue }
            if chars[k] == "(" { paren += 1 }
            if chars[k] == ")" { paren -= 1 }
            if paren == 0 { break }
            k += 1
        }
        guard k < chars.count, chars[k] == ")" else { return nil }

        var raw = String(chars[j + 2..<k]).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("<"), let close = raw.firstIndex(of: ">") {
            raw = String(raw[raw.index(after: raw.startIndex)..<close])
        }
        // Strip an optional link title: "url \"title\""
        if let quote = raw.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            raw = String(raw[..<quote]).trimmingCharacters(in: .whitespaces)
        }
        let children = parseFragment(start + 1..<j)
        return (children, raw, k + 1)
    }

    private func parseAutolink(at start: Int) -> (url: String, end: Int)? {
        guard has("<", at: start) else { return nil }
        var i = start + 1
        while i < chars.count, chars[i] != ">" { i += 1 }
        guard i < chars.count else { return nil }
        let value = String(chars[start + 1..<i])
        guard value.contains("://") || value.hasPrefix("mailto:") else { return nil }
        return (value, i + 1)
    }

    private func bareURL(at start: Int) -> (url: String, end: Int)? {
        var i = start
        while i < chars.count, !chars[i].isWhitespace, chars[i] != ")", chars[i] != "]" { i += 1 }
        var url = String(chars[start..<i])
        while let last = url.last, ".,;:!?。".contains(last) {
            url.removeLast()
            i -= 1
        }
        return url.count > 8 ? (url, i) : nil
    }
}
