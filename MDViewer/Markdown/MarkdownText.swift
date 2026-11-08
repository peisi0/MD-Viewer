import CoreFoundation
import Foundation

/// Pure, actor-independent text utilities. All of these are safe to call from
/// a detached task, which keeps file I/O and parsing off the main thread.
enum MarkdownText {

    static func decode(_ data: Data) -> String {
        let gb18030 = String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, gb18030, .isoLatin1] {
            if let string = String(data: data, encoding: encoding), !string.isEmpty {
                return string
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Lightweight title for library metadata: front matter `title:` or the
    /// first H1. Avoids running the full block parser at app launch.
    static func quickTitle(of text: String, fallback: String) -> String {
        var inFrontMatter = false
        var inspected = 0
        for raw in text.split(separator: "\n", maxSplits: 80, omittingEmptySubsequences: false) {
            inspected += 1
            if inspected > 80 { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" {
                if inFrontMatter { inFrontMatter = false; continue }
                if inspected == 1 { inFrontMatter = true; continue }
            }
            if inFrontMatter, let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "title" {
                    let value = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty { return String(value) }
                }
                continue
            }
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return (fallback as NSString).deletingPathExtension
    }

    /// First meaningful prose line, used for the library card preview.
    /// Caps the scan so importing a huge file never allocates an array of
    /// hundreds of thousands of lines.
    static func preview(of text: String) -> String {
        var inFrontMatter = false
        var inCode = false
        var firstCandidate: String?
        var seen = 0

        for raw in text.split(separator: "\n", maxSplits: 400, omittingEmptySubsequences: false) {
            seen += 1
            if seen > 400 { break }
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line == "---" || line == "..." {
                if inFrontMatter { inFrontMatter = false }
                else if seen == 1 { inFrontMatter = true }
                continue
            }
            if inFrontMatter { continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCode.toggle()
                continue
            }
            guard !inCode, !line.isEmpty else { continue }
            if ["#", ">", "|", "---", "===", "- ", "* ", "+ ", "    "].contains(where: { line.hasPrefix($0) }) {
                continue
            }
            for marker in ["**", "__", "~~", "`", "*", "[", "]"] {
                line = line.replacingOccurrences(of: marker, with: "")
            }
            let candidate = String(line.prefix(110))
            if firstCandidate == nil { firstCandidate = candidate }
            if candidate.count >= 18 { return candidate }
        }
        return firstCandidate ?? "Markdown 文档"
    }
}
