import AVFoundation

final class AudioImporter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "audio.import")

    func importFile(url: URL, pipeline: AudioPipeline) {
        queue.async { [self] in
            AppLog.shared.add("Import started: \(url.lastPathComponent)")
            do {
                let file = try AVAudioFile(forReading: url)
                let inputFormat = file.processingFormat
                let sampleRate = inputFormat.sampleRate
                let duration = Double(file.length) / sampleRate
                let baseTime = Date().timeIntervalSince1970 - duration

                if let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: sampleRate,
                                                    channels: inputFormat.channelCount,
                                                    interleaved: false),
                   inputFormat.commonFormat == .pcmFormatFloat32 {
                    try self.process(file: file,
                                     inputFormat: inputFormat,
                                     outputFormat: outputFormat,
                                     pipeline: pipeline,
                                     baseTime: baseTime)
                } else if let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                          sampleRate: sampleRate,
                                                          channels: inputFormat.channelCount,
                                                          interleaved: false) {
                    try self.processWithConverter(file: file,
                                                  inputFormat: inputFormat,
                                                  outputFormat: outputFormat,
                                                  pipeline: pipeline,
                                                  baseTime: baseTime)
                } else {
                    throw NSError(domain: "AudioImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported audio format"])
                }

                AppLog.shared.add("Import finished: \(url.lastPathComponent)")
            } catch {
                AppLog.shared.add("Import failed: \(error.localizedDescription)")
            }
        }
    }

    private func process(file: AVAudioFile,
                         inputFormat: AVAudioFormat,
                         outputFormat: AVAudioFormat,
                         pipeline: AudioPipeline,
                         baseTime: Double) throws {
        let chunkSize: AVAudioFrameCount = 4096
        var offset: Double = 0
        while file.framePosition < file.length {
            let framesLeft = AVAudioFrameCount(file.length - file.framePosition)
            let frameCount = min(chunkSize, framesLeft)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else { break }
            try file.read(into: buffer, frameCount: frameCount)
            if buffer.frameLength == 0 { break }
            let chunkStart = baseTime + offset
            pipeline.handleImported(buffer: buffer, startTime: chunkStart)
            offset += Double(buffer.frameLength) / outputFormat.sampleRate
        }
    }

    private func processWithConverter(file: AVAudioFile,
                                      inputFormat: AVAudioFormat,
                                      outputFormat: AVAudioFormat,
                                      pipeline: AudioPipeline,
                                      baseTime: Double) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(domain: "AudioImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
        }

        let chunkSize: AVAudioFrameCount = 4096
        var offset: Double = 0
        while file.framePosition < file.length {
            let framesLeft = AVAudioFrameCount(file.length - file.framePosition)
            let frameCount = min(chunkSize, framesLeft)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { break }
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                do {
                    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    try file.read(into: inputBuffer, frameCount: frameCount)
                    outStatus.pointee = inputBuffer.frameLength == 0 ? .endOfStream : .haveData
                    return inputBuffer
                } catch {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            if let error { throw error }
            if status == .endOfStream { break }
            if outputBuffer.frameLength == 0 { continue }
            let chunkStart = baseTime + offset
            pipeline.handleImported(buffer: outputBuffer, startTime: chunkStart)
            offset += Double(outputBuffer.frameLength) / outputFormat.sampleRate
        }
    }
}
