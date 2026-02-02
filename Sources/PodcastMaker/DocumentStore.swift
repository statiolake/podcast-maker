import Foundation

struct DocumentMetadata: Codable {
    let title: String
    let startTime: Double
    let endTime: Double
    let summary: String
    let transcript: String
    let formattedTranscript: String
    let topics: [TopicSegment]
    let createdAt: Double
}

final class DocumentStore {
    private let fileManager = FileManager.default

    func documentsRoot() -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("PodcastMaker", isDirectory: true)
    }

    func saveDocument(title: String, audioData: Data, metadata: DocumentMetadata) -> URL? {
        let root = documentsRoot()
        let dateDir = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: metadata.startTime))
        let safeTitle = sanitize(title)
        let folder = root.appendingPathComponent("\(dateDir)_\(safeTitle)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let audioURL = folder.appendingPathComponent("audio.wav")
            let metaURL = folder.appendingPathComponent("metadata.json")
            try audioData.write(to: audioURL)
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metaURL)
            return folder
        } catch {
            AppLog.shared.add("Document save failed: \(error.localizedDescription)")
            return nil
        }
    }

    func recentDocuments(limit: Int) -> [URL] {
        let root = documentsRoot()
        guard let items = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        return items.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da > db
        }.prefix(limit).map { $0 }
    }

    func loadMetadata(at folder: URL) -> DocumentMetadata? {
        let metaURL = folder.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(DocumentMetadata.self, from: data)
    }

    private func sanitize(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(cleaned).replacingOccurrences(of: "  ", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
