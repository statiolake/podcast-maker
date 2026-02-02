import Foundation

final class SegmentStorage {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let dateFormatter: DateFormatter

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseURL = appSupport.appendingPathComponent("PodcastMaker", isDirectory: true)
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    func saveSegment(samples: [Float], startTime: Double, endTime: Double) -> SegmentRecord? {
        let dateDir = dateFormatter.string(from: Date(timeIntervalSince1970: startTime))
        let dayURL = baseURL.appendingPathComponent(dateDir, isDirectory: true)
        let segmentsURL = dayURL.appendingPathComponent("segments", isDirectory: true)
        let transcriptsURL = dayURL.appendingPathComponent("transcripts", isDirectory: true)

        do {
            try fileManager.createDirectory(at: segmentsURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: transcriptsURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let id = String(format: "%.0f", startTime * 1000)
        let audioFile = "segment_\(id).wav"
        let audioURL = segmentsURL.appendingPathComponent(audioFile)

        guard writeWav16kMono(samples: samples, to: audioURL) else {
            AppLog.shared.add("Segment write failed id=\(id)")
            return nil
        }

        let record = SegmentRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            duration: endTime - startTime,
            audioPath: audioURL.path,
            text: "",
            status: "pending"
        )

        let jsonURL = dayURL.appendingPathComponent("segments.jsonl")
        appendJSONLine(record, to: jsonURL)
        AppLog.shared.add(String(format: "Segment saved id=%@ duration=%.2fs", id, record.duration))

        return record
    }

    func saveTranscript(id: String, startTime: Double, segments: [TranscriptSegment]) {
        let dateDir = dateFormatter.string(from: Date(timeIntervalSince1970: startTime))
        let dayURL = baseURL.appendingPathComponent(dateDir, isDirectory: true)
        let transcriptsURL = dayURL.appendingPathComponent("transcripts", isDirectory: true)
        let transcriptURL = transcriptsURL.appendingPathComponent("segment_\(id).json")

        do {
            try fileManager.createDirectory(at: transcriptsURL, withIntermediateDirectories: true)
        } catch {
            return
        }

        let absoluteSegments = segments.map { segment in
            TranscriptSegment(
                startTime: startTime + segment.startTime,
                endTime: startTime + segment.endTime,
                text: sanitizeTranscriptText(segment.text)
            )
        }

        let record = TranscriptRecord(id: id, startTime: startTime, segments: absoluteSegments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: transcriptURL)
        AppLog.shared.add("Transcript saved id=\(id) segments=\(segments.count)")
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(value) else { return }

        let lineData = data + Data("\n".utf8)
        if fileManager.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: lineData)
                } catch {
                    return
                }
            }
        } else {
            try? lineData.write(to: url)
        }
    }

    private func writeWav16kMono(samples: [Float], to url: URL) -> Bool {
        let sampleRate = UInt32(16000)
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = sampleRate * UInt32(numChannels * bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * bitsPerSample / 8

        var pcmData = Data(capacity: samples.count * 2)
        pcmData.reserveCapacity(samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            var little = int16.littleEndian
            Swift.withUnsafeBytes(of: &little) { pcmData.append(contentsOf: $0) }
        }

        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(withLittleEndian: riffChunkSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withLittleEndian: UInt32(16))
        header.append(withLittleEndian: UInt16(1))
        header.append(withLittleEndian: numChannels)
        header.append(withLittleEndian: sampleRate)
        header.append(withLittleEndian: byteRate)
        header.append(withLittleEndian: blockAlign)
        header.append(withLittleEndian: bitsPerSample)
        header.append("data".data(using: .ascii)!)
        header.append(withLittleEndian: dataChunkSize)

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let outData = header + pcmData
            try outData.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func sanitizeTranscriptText(_ text: String) -> String {
        let pattern = "ご視聴ありがとうございました[！。]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let replaced = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[BLANK_AUDIO]")
        return replaced
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(withLittleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
