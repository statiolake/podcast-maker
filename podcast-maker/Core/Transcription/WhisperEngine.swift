import Foundation
import whisper

final class WhisperASRWorker {
    static let shared = WhisperASRWorker()

    private let queue = DispatchQueue(label: "asr.worker", qos: .utility)
    private var engine: WhisperEngine?
    private var pending: [(SegmentRecord, [Float])] = []

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleModelReady), name: .modelReady, object: nil)
    }

    func enqueue(record: SegmentRecord, samples: [Float], onResult: @escaping (String, Double, [TranscriptSegment]) -> Void) {
        queue.async { [record, samples, weak self] in
            guard let self else { return }
            if self.engine == nil && !self.tryInitEngineIfReady() {
                self.pending.append((record, samples))
                AppLog.shared.add("ASR queued id=\(record.id) (pending=\(self.pending.count))")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .queueUpdated, object: nil)
                }
                return
            }
            self.process(record: record, samples: samples, onResult: onResult)
        }
    }

    func queueStatus() -> (pending: Int, modelReady: Bool, downloading: Bool) {
        let modelStatus = ModelManager.shared.status()
        return queue.sync {
            (pending: pending.count, modelReady: modelStatus.ready, downloading: modelStatus.downloading)
        }
    }

    private func process(record: SegmentRecord, samples: [Float], onResult: @escaping (String, Double, [TranscriptSegment]) -> Void) {
        guard let engine = engine else { return }
        let start = Date()
        let segments = engine.transcribe(samples: samples)
        let elapsed = Date().timeIntervalSince(start)
        let delay = Date().timeIntervalSince1970 - record.endTime
        AppLog.shared.add(String(format: "ASR done id=%@ segments=%d elapsed=%.2fs delay=%.2fs", record.id, segments.count, elapsed, delay))
        onResult(record.id, record.startTime, segments)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .queueUpdated, object: nil)
        }
    }

    private func tryInitEngineIfReady() -> Bool {
        if engine != nil { return true }
        if !ModelManager.shared.status().ready { return false }
        engine = WhisperEngine()
        if engine == nil {
            AppLog.shared.add("Whisper init failed")
            return false
        }
        return true
    }

    @objc private func handleModelReady() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.tryInitEngineIfReady() else { return }
            while !self.pending.isEmpty {
                let (record, samples) = self.pending.removeFirst()
                self.process(record: record, samples: samples, onResult: { id, startTime, segments in
                    SegmentStorage().saveTranscript(id: id, startTime: startTime, segments: segments)
                })
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .queueUpdated, object: nil)
            }
        }
    }
}

extension WhisperASRWorker: @unchecked Sendable {}

final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let timeScale: Double = 0.01
    private let languageCString: UnsafeMutablePointer<CChar>?

    init?() {
        guard let modelPath = Self.findModelPath() else {
            AppLog.shared.add("Whisper model not found")
            return nil
        }
        AppLog.shared.add("Whisper model: \(modelPath)")
        languageCString = strdup("ja")
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = false
        ctx = whisper_init_from_file_with_params(modelPath, params)
        if ctx == nil {
            AppLog.shared.add("Whisper init failed")
            return nil
        }
    }

    deinit {
        if let ctx {
            whisper_free(ctx)
        }
        if let languageCString {
            free(languageCString)
        }
    }

    func transcribe(samples: [Float]) -> [TranscriptSegment] {
        guard let ctx else { return [] }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.detect_language = false
        if let languageCString {
            params.language = UnsafePointer(languageCString)
        }
        params.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        params.offset_ms = 0
        params.duration_ms = 0

        let result = samples.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return whisper_full(ctx, params, base, Int32(buffer.count))
        }
        if result != 0 {
            AppLog.shared.add("Whisper transcription failed (code \(result))")
            return []
        }

        let count = Int(whisper_full_n_segments(ctx))
        if count == 0 {
            return []
        }

        var segments: [TranscriptSegment] = []
        segments.reserveCapacity(count)

        for i in 0..<count {
            let t0 = Double(whisper_full_get_segment_t0(ctx, Int32(i))) * timeScale
            let t1 = Double(whisper_full_get_segment_t1(ctx, Int32(i))) * timeScale
            guard let cText = whisper_full_get_segment_text(ctx, Int32(i)) else { continue }
            let text = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            segments.append(TranscriptSegment(startTime: t0, endTime: t1, text: text))
        }

        return segments
    }

    private static func findModelPath() -> String? {
        return ModelManager.shared.modelPath()
    }
}
