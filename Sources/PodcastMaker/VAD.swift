import Foundation

struct VADConfig {
    let sampleRate: Double = 16000
    let frameMs: Double = 20
    let startMs: Double = 300
    let endMs: Double = 900
    let minLenSeconds: Double = 1.5
    let maxLenSeconds: Double = 120
    let paddingSeconds: Double = 0.3
    let rmsThreshold: Float = 0.015
}

final class VADSegmenter {
    private let config = VADConfig()
    private let frameSamples: Int
    private let startFrames: Int
    private let endFrames: Int
    private let minFrames: Int
    private let maxFrames: Int
    private let paddingFrames: Int
    private let frameDuration: Double

    private var inSpeech = false
    private var voiceBuffer: [[Float]] = []
    private var preRollFrames: [[Float]] = []
    private var segmentFrames: [[Float]] = []
    private var segmentStartTime: Double = 0
    private var lastVoiceFrameIndex: Int = 0
    private var silenceRun = 0

    init() {
        frameSamples = Int(config.sampleRate * config.frameMs / 1000.0)
        frameDuration = Double(frameSamples) / config.sampleRate
        startFrames = max(1, Int(config.startMs / config.frameMs))
        endFrames = max(1, Int(config.endMs / config.frameMs))
        minFrames = max(1, Int(config.minLenSeconds / frameDuration))
        maxFrames = max(minFrames, Int(config.maxLenSeconds / frameDuration))
        paddingFrames = max(0, Int(config.paddingSeconds / frameDuration))
    }

    func process(samples: [Float], startTime: Double, onSegment: (Double, Double, [Float]) -> Void) {
        var cursor = 0
        while cursor + frameSamples <= samples.count {
            let frame = Array(samples[cursor..<(cursor + frameSamples)])
            let frameStartTime = startTime + Double(cursor) / config.sampleRate
            let rms = computeRMS(frame)
            let isVoice = rms >= config.rmsThreshold

            if !inSpeech {
                if isVoice {
                    voiceBuffer.append(frame)
                    if voiceBuffer.count > startFrames {
                        voiceBuffer.removeFirst()
                    }
                    if voiceBuffer.count == startFrames {
                        inSpeech = true
                        segmentStartTime = frameStartTime - Double(startFrames - 1) * frameDuration
                        segmentFrames = preRollFrames + voiceBuffer
                        lastVoiceFrameIndex = segmentFrames.count - 1
                        silenceRun = 0
                        voiceBuffer.removeAll()
                    }
                } else {
                    voiceBuffer.removeAll()
                }

                preRollFrames.append(frame)
                if preRollFrames.count > paddingFrames {
                    preRollFrames.removeFirst()
                }
            } else {
                segmentFrames.append(frame)
                if isVoice {
                    lastVoiceFrameIndex = segmentFrames.count - 1
                    silenceRun = 0
                } else {
                    silenceRun += 1
                }

                if segmentFrames.count >= maxFrames {
                    finalizeSegment(onSegment: onSegment)
                } else if silenceRun >= endFrames {
                    finalizeSegment(onSegment: onSegment)
                }
            }

            cursor += frameSamples
        }
    }

    private func finalizeSegment(onSegment: (Double, Double, [Float]) -> Void) {
        let endFrameIndex = min(lastVoiceFrameIndex + paddingFrames, segmentFrames.count - 1)
        let trimmedFrames = Array(segmentFrames[0...endFrameIndex])
        let totalFrames = trimmedFrames.count

        if totalFrames >= minFrames {
            let samples = trimmedFrames.flatMap { $0 }
            let duration = Double(totalFrames) * frameDuration
            let endTime = segmentStartTime + duration
            onSegment(segmentStartTime, endTime, samples)
        }

        preRollFrames = Array(segmentFrames.suffix(paddingFrames))
        segmentFrames.removeAll()
        inSpeech = false
        silenceRun = 0
    }

    private func computeRMS(_ frame: [Float]) -> Float {
        var sum: Float = 0
        for sample in frame {
            sum += sample * sample
        }
        return sqrt(sum / Float(frame.count))
    }
}
