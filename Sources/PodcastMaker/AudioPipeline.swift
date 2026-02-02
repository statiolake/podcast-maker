import AVFoundation

final class AudioPipeline {
    private let queue = DispatchQueue(label: "audio.pipeline")
    private let storage = SegmentStorage()
    private let vad = VADSegmenter()
    private let asr = WhisperASRWorker()
    private var streamTime: Double?
    private var lastLogTime: TimeInterval = 0
    private var loggedFormat = false

    func handle(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }

        if !loggedFormat {
            loggedFormat = true
            AppLog.shared.add("Audio format: rate=\(buffer.format.sampleRate)Hz channels=\(channels)")
        }

        var mono = [Float](repeating: 0, count: frames)
        if channels == 1 {
            mono = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        } else {
            for c in 0..<channels {
                let channel = channelData[c]
                for i in 0..<frames {
                    mono[i] += channel[i]
                }
            }
            let inv = 1.0 / Float(channels)
            for i in 0..<frames {
                mono[i] *= inv
            }
        }

        let sampleRate = buffer.format.sampleRate
        queue.async { [mono, sampleRate, weak self] in
            self?.processMonoSamples(mono, sampleRate: sampleRate)
        }
    }

    private func processMonoSamples(_ mono: [Float], sampleRate: Double) {
        let duration = Double(mono.count) / sampleRate
        let endTime = Date().timeIntervalSince1970
        let startTime = endTime - duration

        if let last = streamTime, startTime - last > 1.0 {
            streamTime = startTime
        }
        if streamTime == nil {
            streamTime = startTime
        }
        let chunkStart = streamTime!
        streamTime = chunkStart + duration

        let samples16k = resampleTo16k(mono, sampleRate: sampleRate)
        let now = Date().timeIntervalSince1970
        if now - lastLogTime > 5 {
            lastLogTime = now
            let rms = computeRMS(samples16k)
            AppLog.shared.add(String(format: "Audio pipeline alive (chunk=%.2fs rms=%.4f)", duration, rms))
        }
        vad.process(samples: samples16k, startTime: chunkStart) { [weak self] segStart, segEnd, samples in
            guard let self else { return }
            AppLog.shared.add(String(format: "VAD segment ready start=%.2f end=%.2f len=%.2fs", segStart, segEnd, segEnd - segStart))
            guard let record = self.storage.saveSegment(samples: samples, startTime: segStart, endTime: segEnd) else {
                return
            }
            self.asr.enqueue(record: record, samples: samples) { [weak self] id, startTime, segments in
                self?.storage.saveTranscript(id: id, startTime: startTime, segments: segments)
            }
        }
    }

    private func resampleTo16k(_ samples: [Float], sampleRate: Double) -> [Float] {
        if abs(sampleRate - 16000) < 1.0 {
            return samples
        }
        let ratio = 16000.0 / sampleRate
        let outCount = max(1, Int(Double(samples.count) * ratio))
        var output = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let src = Double(i) / ratio
            let i0 = Int(src)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(src - Double(i0))
            output[i] = samples[i0] * (1 - frac) + samples[i1] * frac
        }
        return output
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        if samples.isEmpty { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
