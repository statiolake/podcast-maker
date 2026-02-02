import Foundation

final class AudioMerger {
    struct WavData {
        let sampleRate: UInt32
        let bitsPerSample: UInt16
        let channels: UInt16
        let data: Data
    }

    struct MergeItem {
        let audioPath: String
        let insertSilenceBefore: Bool
    }

    func merge(items: [MergeItem], silenceSeconds: Double = 0.5) -> Data? {
        var merged = Data()
        var format: WavData?

        for item in items {
            guard let wav = readWav(from: URL(fileURLWithPath: item.audioPath)) else { continue }
            if format == nil {
                format = wav
            }
            if wav.sampleRate != format?.sampleRate || wav.bitsPerSample != format?.bitsPerSample || wav.channels != format?.channels {
                continue
            }
            if item.insertSilenceBefore, let fmt = format {
                merged.append(silenceData(seconds: silenceSeconds, format: fmt))
            }
            merged.append(wav.data)
        }

        guard let fmt = format else { return nil }
        return buildWav(sampleRate: fmt.sampleRate, bitsPerSample: fmt.bitsPerSample, channels: fmt.channels, pcmData: merged)
    }

    private func readWav(from url: URL) -> WavData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.count < 44 { return nil }
        let riff = String(data: data[0..<4], encoding: .ascii)
        if riff != "RIFF" { return nil }

        let fmtChunkOffset = 12
        var idx = fmtChunkOffset
        var sampleRate: UInt32 = 16000
        var bitsPerSample: UInt16 = 16
        var channels: UInt16 = 1
        var dataOffset = -1
        var dataSize = 0

        while idx + 8 <= data.count {
            let chunkId = String(data: data[idx..<(idx+4)], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32LE(data, idx + 4))
            if chunkId == "fmt " {
                channels = readUInt16LE(data, idx + 10)
                sampleRate = readUInt32LE(data, idx + 12)
                bitsPerSample = readUInt16LE(data, idx + 22)
            } else if chunkId == "data" {
                dataOffset = idx + 8
                dataSize = chunkSize
                break
            }
            idx += 8 + chunkSize
        }

        if dataOffset < 0 { return nil }
        let end = min(dataOffset + dataSize, data.count)
        let pcm = data[dataOffset..<end]
        return WavData(sampleRate: sampleRate, bitsPerSample: bitsPerSample, channels: channels, data: Data(pcm))
    }

    private func buildWav(sampleRate: UInt32, bitsPerSample: UInt16, channels: UInt16, pcmData: Data) -> Data {
        let byteRate = sampleRate * UInt32(channels * bitsPerSample / 8)
        let blockAlign: UInt16 = channels * bitsPerSample / 8
        let dataChunkSize = UInt32(pcmData.count)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(withLittleEndian: riffChunkSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withLittleEndian: UInt32(16))
        header.append(withLittleEndian: UInt16(1))
        header.append(withLittleEndian: channels)
        header.append(withLittleEndian: sampleRate)
        header.append(withLittleEndian: byteRate)
        header.append(withLittleEndian: blockAlign)
        header.append(withLittleEndian: bitsPerSample)
        header.append("data".data(using: .ascii)!)
        header.append(withLittleEndian: dataChunkSize)

        return header + pcmData
    }

    private func silenceData(seconds: Double, format: WavData) -> Data {
        let bytesPerSample = Int(format.bitsPerSample / 8)
        let frameCount = Int(Double(format.sampleRate) * seconds)
        let byteCount = frameCount * Int(format.channels) * bytesPerSample
        return Data(count: max(0, byteCount))
    }

    private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        let slice = data[offset..<(offset+4)]
        return slice.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }

    private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        let slice = data[offset..<(offset+2)]
        return slice.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(withLittleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
