import Foundation

struct SegmentTranscript {
    let id: String
    let startTime: Double
    let endTime: Double
    let text: String
    let audioPath: String
}

final class TranscriptAggregator {
    private let fileManager = FileManager.default

    func loadRecentSegments(hours: Double) -> [SegmentTranscript] {
        let cutoff = Date().timeIntervalSince1970 - hours * 3600.0
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("PodcastMaker", isDirectory: true)

        guard let dayDirs = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var segments: [SegmentTranscript] = []
        for dayDir in dayDirs {
            let transcriptsURL = dayDir.appendingPathComponent("transcripts", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(at: transcriptsURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file) else { continue }
                guard let record = try? JSONDecoder().decode(TranscriptRecord.self, from: data) else { continue }
                guard let first = record.segments.first, let last = record.segments.last else { continue }
                if last.endTime < cutoff { continue }

                let text = record.segments.map { $0.text }.joined(separator: " ")
                let audioPath = dayDir.appendingPathComponent("segments/segment_\(record.id).wav").path
                let segment = SegmentTranscript(
                    id: record.id,
                    startTime: first.startTime,
                    endTime: last.endTime,
                    text: text,
                    audioPath: audioPath
                )
                segments.append(segment)
            }
        }

        return segments.sorted { $0.startTime < $1.startTime }
    }

    func combinedTranscriptText(segments: [SegmentTranscript]) -> String {
        segments.map { seg in
            let start = String(format: "%.2f", seg.startTime)
            let end = String(format: "%.2f", seg.endTime)
            return "\(start)|\(end)|\(seg.text)"
        }.joined(separator: "\n")
    }
}
