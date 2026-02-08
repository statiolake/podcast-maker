import Foundation

final class TranscriptPreviewStore {
    static let shared = TranscriptPreviewStore()

    private let queue = DispatchQueue(label: "transcript.preview")
    private var entries: [String] = []
    private let maxLines = 200

    private init() {}

    func append(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async {
            self.entries.append(trimmed)
            if self.entries.count > self.maxLines {
                self.entries.removeFirst(self.entries.count - self.maxLines)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .transcriptPreviewUpdated, object: nil)
            }
        }
    }

    func allText() -> String {
        queue.sync { entries.joined(separator: "\n") }
    }

    func lastLine() -> String {
        queue.sync { entries.last ?? "" }
    }
}

extension TranscriptPreviewStore: @unchecked Sendable {}
