import Foundation

/// Line-oriented block parser for GitHub-flavoured Markdown.
/// Stage 1 of the rendering pipeline: text → `[MarkdownBlock]`.
struct MarkdownParser {

    func parse(_ raw: String, fallbackTitle: String) -> MarkdownDocument {
        var lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var frontMatter: [(key: String, value: String)] = []
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" {
            var closing = -1
            for idx in 1..<lines.count {
                let t = lines[idx].trimmingCharacters(in: .whitespaces)
                if t == "---" || t == "..." { closing = idx; break }
            }
            if closing > 1 {
                for idx in 1..<closing {
                    let l = lines[idx]
                    guard let colon = l.firstIndex(of: ":") else { continue }
                    let key = String(l[..<colon]).trimmingCharacters(in: .whitespaces)
                    var value = String(l[l.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !key.isEmpty, !value.isEmpty {
                        frontMatter.append((key: key, value: value))
                    }
                }
                lines = Array(lines[(closing + 1)...])
            }
        }

        let generator = BlockIDGenerator()
        let blocks = parseBlocks(lines, gen: generator)

        var headings: [HeadingItem] = []
        collectHeadings(blocks, into: &headings, generator: BlockIDGenerator())

        let textMap = blockTextMap(blocks)
        // Reuse the precomputed strings instead of walking the tree a second time.
        let body = blocks.map { textMap[$0.id] ?? "" }.joined(separator: "\n")
        let fullText = (frontMatter.map(\.value) + [body]).joined(separator: "\n")
        let words = countWords(body)

        var title = frontMatter.first(where: { $0.key.lowercased() == "title" })?.value ?? ""
        if title.isEmpty { title = headings.first(where: { $0.level == 1 })?.text ?? "" }
        if title.isEmpty { title = (fallbackTitle as NSString).deletingPathExtension }

        return MarkdownDocument(
            title: title,
            frontMatter: frontMatter,
            blocks: blocks,
            headings: headings,
            plainText: fullText,
            blockText: textMap,
            wordCount: words,
            readingMinutes: max(1, Int(ceil(Double(words) / 320.0)))
        )
    }

    // MARK: - Block loop

    private func parseBlocks(_ lines: [String], gen: BlockIDGenerator) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }

            // Fenced code
            if let fence = openingFence(line) {
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if isClosingFence(lines[i], marker: fence.marker, minimum: fence.count) {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let language = fence.language.isEmpty ? nil : fence.language
                blocks.append(MarkdownBlock(id: gen.next(),
                                            kind: .code(language: language,
                                                        code: codeLines.joined(separator: "\n"))))
                continue
            }

            // ATX heading
            if let heading = atxHeading(line) {
                var inline = InlineParser(heading.text)
                let nodes = inline.parse()
                blocks.append(MarkdownBlock(id: gen.next(),
                                            kind: .heading(level: heading.level,
                                                           inline: nodes,
                                                           plain: inlinePlainText(nodes))))
                i += 1
                continue
            }

            // Setext heading (checked before paragraph, after rule)
            if !isRule(line), i + 1 < lines.count, let level = setextLevel(lines[i + 1]) {
                let text = line.trimmingCharacters(in: .whitespaces)
                var inline = InlineParser(text)
                let nodes = inline.parse()
                blocks.append(MarkdownBlock(id: gen.next(),
                                            kind: .heading(level: level, inline: nodes,
                                                           plain: inlinePlainText(nodes))))
                i += 2
                continue
            }

            // Horizontal rule
            if isRule(line) {
                blocks.append(MarkdownBlock(id: gen.next(), kind: .rule))
                i += 1
                continue
            }

            // Blockquote (supports nested quotes and blank lines inside a quote)
            if String(line.drop(while: { $0 == " " })).hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        var rest = String(t.dropFirst())
                        if rest.hasPrefix(" ") { rest.removeFirst() }
                        quoted.append(rest)
                        i += 1
                    } else if isBlank(lines[i]) {
                        var j = i
                        while j < lines.count, isBlank(lines[j]) { j += 1 }
                        if j < lines.count,
                           lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                            while i < j { quoted.append(""); i += 1 }
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }
                let children = parseBlocks(quoted, gen: gen)
                blocks.append(MarkdownBlock(id: gen.next(), kind: .quote(children)))
                continue
            }

            // GFM table
            if line.contains("|"), i + 1 < lines.count,
               let alignments = tableSeparator(lines[i + 1]) {
                let headerCells = splitTableRow(line).map { cell in
                    var p = InlineParser(cell); return p.parse()
                }
                i += 2
                var rows: [[[InlineNode]]] = []
                while i < lines.count, lines[i].contains("|"), !isBlank(lines[i]) {
                    rows.append(splitTableRow(lines[i]).map { cell in
                        var p = InlineParser(cell); return p.parse()
                    })
                    i += 1
                }
                blocks.append(MarkdownBlock(id: gen.next(),
                                            kind: .table(header: headerCells,
                                                         alignments: alignments,
                                                         rows: rows)))
                continue
            }

            // Lists (nested lists flattened with an indentation depth)
            if let firstMarker = listMarker(line) {
                let baseIndent = firstMarker.indent
                var entries: [ListEntry] = []
                var counters: [Int: Int] = [:]
                var safety = 0

                while i < lines.count, safety < 1000 {
                    safety += 1
                    guard let marker = listMarker(lines[i]), marker.indent >= baseIndent else { break }
                    let depth = max(0, (marker.indent - baseIndent) / 2)
                    var contentLines = [marker.text]
                    i += 1

                    while i < lines.count {
                        if listMarker(lines[i]) != nil { break }
                        if isBlank(lines[i]) {
                            var j = i
                            while j < lines.count, isBlank(lines[j]) { j += 1 }
                            if j < lines.count,
                               let next = listMarker(lines[j]), next.indent >= baseIndent {
                                i = j
                            }
                            break
                        }
                        if indent(of: lines[i]) >= baseIndent + 2 {
                            contentLines.append(String(lines[i].dropFirst(min(lines[i].count, baseIndent + 2))))
                            i += 1
                        } else {
                            break
                        }
                    }

                    let text = contentLines.joined(separator: " ")
                    var inline = InlineParser(text)
                    let nodes = inline.parse()
                    if marker.ordered { counters[depth, default: 0] += 1 }
                    entries.append(ListEntry(
                        id: gen.next(),
                        depth: depth,
                        ordered: marker.ordered,
                        number: marker.ordered ? (counters[depth] ?? 1) : 0,
                        checked: marker.checked,
                        inline: nodes
                    ))
                }

                blocks.append(MarkdownBlock(id: gen.next(), kind: .list(entries: entries)))
                continue
            }

            // Paragraph
            var paragraphLines: [String] = []
            while i < lines.count, !isBlank(lines[i]) {
                let next = i + 1 < lines.count ? lines[i + 1] : ""
                if !paragraphLines.isEmpty, startsBlock(lines[i], next: next) { break }
                paragraphLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                i += 1
            }
            if paragraphLines.isEmpty {
                paragraphLines.append(line.trimmingCharacters(in: .whitespaces))
                i += 1
            }

            var inline = InlineParser(paragraphLines.joined(separator: "\n"))
            let nodes = inline.parse()
            if nodes.count == 1, case .image(let alt, let src) = nodes[0] {
                blocks.append(MarkdownBlock(id: gen.next(), kind: .image(alt: alt, src: src)))
            } else {
                blocks.append(MarkdownBlock(id: gen.next(), kind: .paragraph(nodes)))
            }
        }

        return blocks
    }

    // MARK: - Line classifiers

    private func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func indent(of line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += 4 }
            else { break }
        }
        return n
    }

    private func openingFence(_ line: String) -> (marker: Character, count: Int, language: String)? {
        let body = String(line.drop(while: { $0 == " " }))
        guard let first = body.first, first == "`" || first == "~" else { return nil }
        var count = 0
        for ch in body { if ch == first { count += 1 } else { break } }
        guard count >= 3 else { return nil }
        let info = String(body.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        let language = info.components(separatedBy: .whitespaces).first ?? ""
        return (first, count, language)
    }

    private func isClosingFence(_ line: String, marker: Character, minimum: Int) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, body.allSatisfy({ $0 == marker }) else { return false }
        return body.count >= minimum
    }

    private func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let body = String(line.drop(while: { $0 == " " }))
        var level = 0
        for ch in body { if ch == "#" { level += 1 } else { break } }
        guard (1...6).contains(level), body.count > level else { return nil }
        let idx = body.index(body.startIndex, offsetBy: level)
        guard body[idx] == " " else { return nil }
        var text = String(body[idx...]).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        return (level, text)
    }

    private func setextLevel(_ line: String) -> Int? {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.allSatisfy({ $0 == "=" }) { return 1 }
        if s.count >= 3, s.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private func isRule(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespaces)
        guard s.count >= 3, let marker = s.first,
              marker == "-" || marker == "*" || marker == "_" else { return false }
        var count = 0
        for ch in s {
            if ch == marker { count += 1 }
            else if ch != " " { return false }
        }
        return count >= 3
    }

    private func listMarker(_ line: String) -> (indent: Int, ordered: Bool, text: String, checked: Bool?)? {
        let ind = indent(of: line)
        let body = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        let arr = Array(body)

        if arr.count >= 2, "-*+".contains(arr[0]), arr[1] == " " {
            var text = String(arr[2...])
            let checked = stripTaskMarker(&text)
            return (ind, false, text, checked)
        }

        var digits = 0
        while digits < arr.count, arr[digits].isNumber { digits += 1 }
        if digits > 0, digits + 1 < arr.count,
           arr[digits] == "." || arr[digits] == ")", arr[digits + 1] == " " {
            var text = String(arr[(digits + 2)...])
            let checked = stripTaskMarker(&text)
            return (ind, true, text, checked)
        }
        return nil
    }

    private func stripTaskMarker(_ text: inout String) -> Bool? {
        let prefixes: [(String, Bool)] = [("[ ] ", false), ("[x] ", true), ("[X] ", true)]
        for (prefix, value) in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            return value
        }
        return nil
    }

    private func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in s {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func tableSeparator(_ line: String) -> [ColumnAlignment]? {
        guard line.contains("-") else { return nil }
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return nil }
        var result: [ColumnAlignment] = []
        for cell in cells {
            var core = cell
            let left = core.hasPrefix(":")
            let right = core.hasSuffix(":")
            if left { core = String(core.dropFirst()) }
            if right { core = String(core.dropLast()) }
            guard core.count >= 1, core.allSatisfy({ $0 == "-" }) else { return nil }
            if left && right { result.append(.center) }
            else if right { result.append(.trailing) }
            else { result.append(.leading) }
        }
        return result
    }

    private func startsBlock(_ line: String, next: String) -> Bool {
        if isBlank(line) { return true }
        if openingFence(line) != nil { return true }
        if atxHeading(line) != nil { return true }
        if isRule(line) { return true }
        if String(line.drop(while: { $0 == " " })).hasPrefix(">") { return true }
        if listMarker(line) != nil { return true }
        if line.contains("|"), tableSeparator(next) != nil { return true }
        return false
    }
}
