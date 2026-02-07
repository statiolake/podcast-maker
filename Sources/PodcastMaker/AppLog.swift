import Foundation

enum LogEvent {
    static let maxLines = 1000
}

final class AppLog {
    static let shared = AppLog()
    private let queue = DispatchQueue(label: "app.log")
    private var entries: [String] = []
    private let timeFormatter: DateFormatter

    private init() {
        timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"
    }

    func add(_ message: String) {
        let time = timeFormatter.string(from: Date())
        let line = "[\(time)] \(message)"
        queue.async {
            self.entries.append(line)
            if self.entries.count > LogEvent.maxLines {
                self.entries.removeFirst(self.entries.count - LogEvent.maxLines)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .logUpdated, object: nil)
            }
        }
    }

    func allText() -> String {
        queue.sync { entries.joined(separator: "\n") }
    }
}

extension Notification.Name {
    static let logUpdated = Notification.Name("PodcastMakerLogUpdated")
    static let modelReady = Notification.Name("PodcastMakerModelReady")
    static let queueUpdated = Notification.Name("PodcastMakerQueueUpdated")
    static let recordingStateChanged = Notification.Name("PodcastMakerRecordingStateChanged")
    static let transcriptPreviewUpdated = Notification.Name("PodcastMakerTranscriptPreviewUpdated")
    static let audioLevelUpdated = Notification.Name("PodcastMakerAudioLevelUpdated")
}
