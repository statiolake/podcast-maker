import Cocoa
import AVFoundation
import AWSBedrockRuntime
import AWSSDKIdentity
import whisper

private enum LogEvent {
    static let maxLines = 1000
}

private final class AppLog {
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

private extension Notification.Name {
    static let logUpdated = Notification.Name("PodcastMakerLogUpdated")
}

private enum DefaultsKey {
    static let awsProfile = "awsProfile"
    static let inputTokens = "bedrockInputTokens"
    static let outputTokens = "bedrockOutputTokens"
    static let cacheWrite5mTokens = "bedrockCacheWrite5mTokens"
    static let cacheWrite1hTokens = "bedrockCacheWrite1hTokens"
    static let cacheHitTokens = "bedrockCacheHitTokens"
}

private struct HaikuPricing {
    static let modelId = "global.anthropic.claude-haiku-4-5-20251001-v1:0"
    static let inputPerMTok: Double = 1.0
    static let cacheWrite5mPerMTok: Double = 1.25
    static let cacheWrite1hPerMTok: Double = 2.0
    static let cacheHitPerMTok: Double = 0.10
    static let outputPerMTok: Double = 5.0
}

private struct BedrockUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheHitTokens: Int
}

private final class BedrockService {
    private let tracker: CostTracker
    private let region: String

    init(tracker: CostTracker) {
        self.tracker = tracker
        self.region = ProcessInfo.processInfo.environment["AWS_REGION"] ?? "us-east-1"
    }

    func test(prompt: String, profile: String) async throws -> String {
        AppLog.shared.add("Bedrock test started (profile=\(profile.isEmpty ? "default" : profile))")
        let response = try await invoke(prompt: prompt, profile: profile)
        tracker.recordUsage(
            input: response.usage.inputTokens,
            output: response.usage.outputTokens,
            cacheWrite5m: response.usage.cacheWrite5mTokens,
            cacheWrite1h: response.usage.cacheWrite1hTokens,
            cacheHit: response.usage.cacheHitTokens
        )
        AppLog.shared.add("Bedrock test succeeded (input=\(response.usage.inputTokens), output=\(response.usage.outputTokens))")
        return response.text
    }

    private func invoke(prompt: String, profile: String) async throws -> (text: String, usage: BedrockUsage) {
        if !profile.isEmpty {
            setenv("AWS_PROFILE", profile, 1)
        }

        var config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
        if !profile.isEmpty {
            let resolver = ProfileAWSCredentialIdentityResolver(profileName: profile)
            config.awsCredentialIdentityResolver = resolver
        }

        let client = BedrockRuntimeClient(config: config)
        let message = BedrockRuntimeClientTypes.Message(
            content: [.text(prompt)],
            role: .user
        )

        var inference = BedrockRuntimeClientTypes.InferenceConfiguration()
        inference.maxTokens = 200
        inference.temperature = 0.2

        let input = ConverseInput(
            inferenceConfig: inference,
            messages: [message],
            modelId: HaikuPricing.modelId
        )

        let output = try await client.converse(input: input)

        let text: String
        if let response = output.output {
            switch response {
            case .message(let message):
                text = message.content?.compactMap { block in
                    switch block {
                    case .text(let value): return value
                    default: return nil
                    }
                }.joined() ?? ""
            case .sdkUnknown:
                text = ""
            }
        } else {
            text = ""
        }

        let usage = BedrockUsage(
            inputTokens: Int(output.usage?.inputTokens ?? 0),
            outputTokens: Int(output.usage?.outputTokens ?? 0),
            cacheWrite5mTokens: 0,
            cacheWrite1hTokens: 0,
            cacheHitTokens: 0
        )

        return (text: text, usage: usage)
    }
}

private final class CostTracker {
    private let defaults = UserDefaults.standard

    var awsProfile: String {
        get { defaults.string(forKey: DefaultsKey.awsProfile) ?? "" }
        set { defaults.set(newValue, forKey: DefaultsKey.awsProfile) }
    }

    var inputTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.inputTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.inputTokens) }
    }

    var outputTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.outputTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.outputTokens) }
    }

    var cacheWrite5mTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheWrite5mTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheWrite5mTokens) }
    }

    var cacheWrite1hTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheWrite1hTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheWrite1hTokens) }
    }

    var cacheHitTokens: Int {
        get { defaults.integer(forKey: DefaultsKey.cacheHitTokens) }
        set { defaults.set(newValue, forKey: DefaultsKey.cacheHitTokens) }
    }

    func recordUsage(input: Int, output: Int, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheHit: Int = 0) {
        inputTokens += input
        outputTokens += output
        cacheWrite5mTokens += cacheWrite5m
        cacheWrite1hTokens += cacheWrite1h
        cacheHitTokens += cacheHit
    }

    func totalCostUSD() -> Double {
        let inputCost = Double(inputTokens) / 1_000_000.0 * HaikuPricing.inputPerMTok
        let outputCost = Double(outputTokens) / 1_000_000.0 * HaikuPricing.outputPerMTok
        let cache5mCost = Double(cacheWrite5mTokens) / 1_000_000.0 * HaikuPricing.cacheWrite5mPerMTok
        let cache1hCost = Double(cacheWrite1hTokens) / 1_000_000.0 * HaikuPricing.cacheWrite1hPerMTok
        let cacheHitCost = Double(cacheHitTokens) / 1_000_000.0 * HaikuPricing.cacheHitPerMTok
        return inputCost + outputCost + cache5mCost + cache1hCost + cacheHitCost
    }
}

private final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let tracker: CostTracker
    private let bedrock: BedrockService
    private let awsField = NSTextField(string: "")
    private let inputTokensLabel = NSTextField(labelWithString: "")
    private let outputTokensLabel = NSTextField(labelWithString: "")
    private let cacheTokensLabel = NSTextField(labelWithString: "")
    private let totalCostLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Bedrock status: idle")
    private let testButton = NSButton(title: "Test Bedrock", target: nil, action: nil)
    private let tabView = NSTabView()
    private let logTextView = NSTextView()

    init(tracker: CostTracker, bedrock: BedrockService) {
        self.tracker = tracker
        self.bedrock = bedrock
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        super.init(window: window)
        setupUI()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLogs), name: .logUpdated, object: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "Bedrock (Claude Haiku 4.5)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        let modelLabel = NSTextField(labelWithString: "Model: \(HaikuPricing.modelId)")
        modelLabel.font = NSFont.systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        testButton.target = self
        testButton.action = #selector(runBedrockTest)

        let awsLabel = NSTextField(labelWithString: "AWS_PROFILE")
        awsField.placeholderString = "default"
        awsField.delegate = self

        let tokensTitle = NSTextField(labelWithString: "Token Usage")
        tokensTitle.font = NSFont.boldSystemFont(ofSize: 12)

        let stack = NSStackView(views: [
            titleLabel,
            modelLabel,
            awsLabel,
            awsField,
            tokensTitle,
            inputTokensLabel,
            outputTokensLabel,
            cacheTokensLabel,
            totalCostLabel,
            statusLabel,
            testButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let settingsView = NSView()
        settingsView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: settingsView.topAnchor, constant: 20)
        ])

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.string = AppLog.shared.allText()

        let scrollView = NSScrollView()
        scrollView.documentView = logTextView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let logView = NSView()
        logView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: logView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: logView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: logView.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: logView.bottomAnchor, constant: -12)
        ])

        tabView.translatesAutoresizingMaskIntoConstraints = false
        let settingsTab = NSTabViewItem(identifier: "settings")
        settingsTab.label = "Settings"
        settingsTab.view = settingsView
        let logTab = NSTabViewItem(identifier: "log")
        logTab.label = "Log"
        logTab.view = logView
        tabView.addTabViewItem(settingsTab)
        tabView.addTabViewItem(logTab)

        content.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: content.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        tracker.awsProfile = awsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refresh() {
        awsField.stringValue = tracker.awsProfile
        inputTokensLabel.stringValue = "Input tokens: \(tracker.inputTokens)"
        outputTokensLabel.stringValue = "Output tokens: \(tracker.outputTokens)"
        cacheTokensLabel.stringValue = "Cache tokens (5m/1h/hit): \(tracker.cacheWrite5mTokens) / \(tracker.cacheWrite1hTokens) / \(tracker.cacheHitTokens)"
        totalCostLabel.stringValue = String(format: "Estimated total cost: $%.4f", tracker.totalCostUSD())
    }

    @objc private func runBedrockTest() {
        testButton.isEnabled = false
        statusLabel.stringValue = "Bedrock status: running..."

        let profile = tracker.awsProfile
        let prompt = "Return a single short sentence saying hello."

        Task {
            do {
                _ = try await bedrock.test(prompt: prompt, profile: profile)
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                    self?.statusLabel.stringValue = "Bedrock status: success"
                    self?.testButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    AppLog.shared.add("Bedrock test failed: \(error.localizedDescription)")
                    self?.statusLabel.stringValue = "Bedrock status: error"
                    self?.testButton.isEnabled = true
                }
            }
        }
    }

    @objc private func refreshLogs() {
        logTextView.string = AppLog.shared.allText()
        logTextView.scrollToEndOfDocument(nil)
    }
}

private struct VADConfig {
    let sampleRate: Double = 16000
    let frameMs: Double = 20
    let startMs: Double = 300
    let endMs: Double = 900
    let minLenSeconds: Double = 1.5
    let maxLenSeconds: Double = 120
    let paddingSeconds: Double = 0.3
    let rmsThreshold: Float = 0.015
}

private struct SegmentRecord: Codable {
    let id: String
    let startTime: Double
    let endTime: Double
    let duration: Double
    let audioPath: String
    let text: String
    let status: String
}

private final class SegmentStorage {
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
                text: segment.text
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
}

private struct TranscriptRecord: Codable {
    let id: String
    let startTime: Double
    let segments: [TranscriptSegment]
}

private struct TranscriptSegment: Codable {
    let startTime: Double
    let endTime: Double
    let text: String
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(withLittleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}

private final class VADSegmenter {
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

private final class AudioPipeline {
    private let queue = DispatchQueue(label: "audio.pipeline")
    private let storage = SegmentStorage()
    private let vad = VADSegmenter()
    private let asr = WhisperASRWorker()
    private var streamTime: Double?

    func handle(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }

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
        vad.process(samples: samples16k, startTime: chunkStart) { [weak self] segStart, segEnd, samples in
            guard let self else { return }
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
}

private final class WhisperASRWorker {
    private let queue = DispatchQueue(label: "asr.worker", qos: .utility)
    private var engine: WhisperEngine?

    func enqueue(record: SegmentRecord, samples: [Float], onResult: @escaping (String, Double, [TranscriptSegment]) -> Void) {
        queue.async { [record, samples, weak self] in
            guard let self else { return }
            if self.engine == nil {
                self.engine = WhisperEngine()
            }
            guard let engine = self.engine else {
                AppLog.shared.add("Whisper engine unavailable (model missing?)")
                return
            }
            let start = Date()
            let segments = engine.transcribe(samples: samples)
            let elapsed = Date().timeIntervalSince(start)
            let delay = Date().timeIntervalSince1970 - record.endTime
            AppLog.shared.add(String(format: "ASR done id=%@ segments=%d elapsed=%.2fs delay=%.2fs", record.id, segments.count, elapsed, delay))
            onResult(record.id, record.startTime, segments)
        }
    }
}

private final class WhisperEngine {
    private var ctx: OpaquePointer?
    private let timeScale: Double = 0.01

    init?() {
        guard let modelPath = Self.findModelPath() else {
            AppLog.shared.add("Whisper model not found in Resources/whisper/models")
            return nil
        }
        AppLog.shared.add("Whisper model: \(modelPath)")
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
    }

    func transcribe(samples: [Float]) -> [TranscriptSegment] {
        guard let ctx else { return [] }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
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
        let bundle = Bundle.main
        if let modelsURL = bundle.resourceURL?.appendingPathComponent("whisper/models", isDirectory: true),
           let files = try? FileManager.default.contentsOfDirectory(atPath: modelsURL.path) {
            if let gguf = files.first(where: { $0.hasSuffix(".gguf") }) {
                return modelsURL.appendingPathComponent(gguf).path
            }
            if let bin = files.first(where: { $0.hasSuffix(".bin") }) {
                return modelsURL.appendingPathComponent(bin).path
            }
        }
        return nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum AppState {
        case recording
        case paused
        case error(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")

    private let audioEngine = AVAudioEngine()
    private let pipeline = AudioPipeline()
    private let costTracker = CostTracker()
    private lazy var bedrockService = BedrockService(tracker: costTracker)
    private var settingsWindow: SettingsWindowController?
    private var isPaused = false
    private var state: AppState = .paused {
        didSet { updateUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        AppLog.shared.add("App launched")
        requestMicAccessAndStart()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
        } else {
            statusItem.button?.title = "PAUSE"
        }

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateUI()
    }

    private func requestMicAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            AppLog.shared.add("Mic permission already authorized")
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        AppLog.shared.add("Mic permission granted")
                        self.startEngine()
                    } else {
                        AppLog.shared.add("Mic permission denied")
                        self.state = .error("Mic permission denied")
                    }
                }
            }
        default:
            AppLog.shared.add("Mic permission denied")
            state = .error("Mic permission denied")
        }
    }

    private func startEngine() {
        let input = audioEngine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 1024

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if self.isPaused {
                return
            }
            self.pipeline.handle(buffer: buffer)
        }

        do {
            try audioEngine.start()
            isPaused = false
            state = .recording
            AppLog.shared.add("Audio engine started")
        } catch {
            AppLog.shared.add("Audio engine start failed: \(error.localizedDescription)")
            state = .error("Audio start failed")
        }
    }

    private func stopEngineIfRunning() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func updateUI() {
        switch state {
        case .recording:
            pauseItem.title = "Pause"
            stateItem.title = "Recording"
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "REC"
            }
        case .paused:
            pauseItem.title = "Resume"
            stateItem.title = "Paused"
            statusItem.button?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "PAUSE"
            }
        case .error(let message):
            pauseItem.title = "Resume"
            stateItem.title = "Error: \(message)"
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "ERR"
            }
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            AppLog.shared.add("Paused")
            state = .paused
        } else {
            AppLog.shared.add("Resumed")
            state = .recording
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(tracker: costTracker, bedrock: bedrockService)
        }
        settingsWindow?.refresh()
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        stopEngineIfRunning()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
