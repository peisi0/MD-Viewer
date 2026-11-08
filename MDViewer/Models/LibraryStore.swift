import Foundation
import Observation
import UniformTypeIdentifiers

struct StoredDocument: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var fileName: String
    var addedAt: Date
    var lastOpenedAt: Date?
    var isSample: Bool
    var wordCount: Int
    var preview: String
}

extension UTType {
    static var markdownDocument: UTType {
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }

    static var importableTypes: [UTType] {
        var types: [UTType] = [.markdownDocument, .plainText, .text]
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdtxt"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        var seen: Set<String> = []
        return types.filter { seen.insert($0.identifier).inserted }
    }
}

@MainActor
@Observable
final class LibraryStore {
    var documents: [StoredDocument] = []
    var errorMessage: String?

    private let fileManager = FileManager.default

    init() {
        bootstrap()
    }

    // MARK: - Paths

    private var supportDirectory: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MDViewer", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var importedDirectory: URL {
        let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imported", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var indexURL: URL {
        supportDirectory.appendingPathComponent("library.json")
    }

    private var sampleDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Samples", isDirectory: true)
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([StoredDocument].self, from: data) {
            documents = saved.filter { document in
                document.isSample ||
                fileManager.fileExists(atPath: importedDirectory.appendingPathComponent(document.fileName).path)
            }
        }
        if !UserDefaults.standard.bool(forKey: "mdv.seeded") {
            seedSamples()
            UserDefaults.standard.set(true, forKey: "mdv.seeded")
        }
        sort()
    }

    private func sampleFileNames() -> [String] {
        guard let dir = sampleDirectory,
              let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.lowercased().hasSuffix(".md") }.sorted()
    }

    func seedSamples() {
        for name in sampleFileNames() where !documents.contains(where: { $0.isSample && $0.fileName == name }) {
            if let sample = makeSample(name: name) { documents.append(sample) }
        }
        sort()
        save()
    }

    private func makeSample(name: String) -> StoredDocument? {
        guard let url = sampleDirectory?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url) else { return nil }
        let text = MarkdownText.decode(data)
        // Bundled sample filenames are ASCII (safe for every IPA unzipper);
        // the Chinese display name comes from the document's own metadata.
        return StoredDocument(
            id: UUID(),
            name: MarkdownText.quickTitle(of: text, fallback: name),
            fileName: name,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            isSample: true,
            wordCount: countWords(text),
            preview: MarkdownText.preview(of: text)
        )
    }

    // MARK: - Reading

    func content(of document: StoredDocument) -> String {
        guard let data = try? Data(contentsOf: url(for: document)) else { return "" }
        return MarkdownText.decode(data)
    }

    /// File read + encoding detection moved off the main actor (used when
    /// copying the Markdown source of a large document).
    func contentAsync(of document: StoredDocument) async -> String {
        let fileURL = url(for: document)
        return await Task.detached(priority: .userInitiated) { () -> String in
            let data = (try? Data(contentsOf: fileURL)) ?? Data()
            return MarkdownText.decode(data)
        }.value
    }

    func url(for document: StoredDocument) -> URL {
        if document.isSample {
            return sampleDirectory?.appendingPathComponent(document.fileName)
                ?? importedDirectory.appendingPathComponent(document.fileName)
        }
        return importedDirectory.appendingPathComponent(document.fileName)
    }

    // MARK: - Import

    @discardableResult
    func importFile(_ source: URL) async -> StoredDocument? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: source) else {
            errorMessage = "无法读取文件：\(source.lastPathComponent)"
            return nil
        }
        let name = source.lastPathComponent
        let directory = importedDirectory

        if let index = documents.firstIndex(where: { !$0.isSample && $0.name == name }) {
            var updated = documents[index]
            let target = directory.appendingPathComponent(updated.fileName)
            let prepared = await Task.detached(priority: .userInitiated) { () -> (String, Int, Bool) in
                let text = MarkdownText.decode(data)
                let written = (try? data.write(to: target, options: .atomic)) != nil
                return (MarkdownText.preview(of: text), countWords(text), written)
            }.value
            guard prepared.2 else {
                errorMessage = "导入失败：无法写入 \(name)"
                return nil
            }
            updated.addedAt = Date()
            updated.wordCount = prepared.1
            updated.preview = prepared.0
            updated.lastOpenedAt = Date()
            documents[index] = updated
            sort()
            save()
            return updated
        }

        let storedName = "\(UUID().uuidString)-\(name)"
        let target = directory.appendingPathComponent(storedName)
        let prepared = await Task.detached(priority: .userInitiated) { () -> (String, Int, Bool) in
            let text = MarkdownText.decode(data)
            let written = (try? data.write(to: target, options: .atomic)) != nil
            return (MarkdownText.preview(of: text), countWords(text), written)
        }.value
        guard prepared.2 else {
            errorMessage = "导入失败：无法写入 \(name)"
            return nil
        }

        let document = StoredDocument(
            id: UUID(), name: name, fileName: storedName,
            addedAt: Date(), lastOpenedAt: Date(), isSample: false,
            wordCount: prepared.1, preview: prepared.0
        )
        documents.insert(document, at: 0)
        save()
        return document
    }

    func importDroppedText(_ text: String, named name: String) async -> StoredDocument? {
        guard let data = text.data(using: .utf8) else { return nil }
        let storedName = "\(UUID().uuidString)-\(name)"
        let target = importedDirectory.appendingPathComponent(storedName)
        let prepared = await Task.detached(priority: .userInitiated) { () -> (String, Int, Bool) in
            let written = (try? data.write(to: target, options: .atomic)) != nil
            return (MarkdownText.preview(of: text), countWords(text), written)
        }.value
        guard prepared.2 else {
            errorMessage = "保存失败：无法写入 \(name)"
            return nil
        }
        let document = StoredDocument(
            id: UUID(), name: name, fileName: storedName,
            addedAt: Date(), lastOpenedAt: Date(), isSample: false,
            wordCount: prepared.1, preview: prepared.0
        )
        documents.insert(document, at: 0)
        save()
        return document
    }

    // MARK: - Mutation

    func touch(_ document: StoredDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents[index].lastOpenedAt = Date()
        sort()
        save()
    }

    func delete(_ document: StoredDocument) {
        if !document.isSample {
            try? fileManager.removeItem(at: importedDirectory.appendingPathComponent(document.fileName))
        }
        documents.removeAll { $0.id == document.id }
        save()
    }

    func clearImported() {
        for document in documents where !document.isSample {
            try? fileManager.removeItem(at: importedDirectory.appendingPathComponent(document.fileName))
        }
        documents.removeAll { !$0.isSample }
        save()
    }

    var importedCount: Int { documents.filter { !$0.isSample }.count }

    private func sort() {
        documents.sort { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Text utilities
    // Heavy text work lives in MarkdownText (actor-independent) so it can run
    // in a detached task instead of blocking the main thread.
}
