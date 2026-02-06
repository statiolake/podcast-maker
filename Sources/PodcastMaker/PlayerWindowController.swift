import Cocoa
import AVFoundation

final class PlayerWindowController: NSWindowController {
    private let audioURL: URL
    private let metadata: DocumentMetadata
    private var player: AVAudioPlayer?
    private var timer: Timer?

    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let summaryLabelField = NSTextField(labelWithString: "")
    private let transcriptLabelField = NSTextField(labelWithString: "")
    private let playButton = NSButton(title: "再生", target: nil, action: nil)
    private let seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let currentTimeLabel = NSTextField(labelWithString: "00:00")
    private let durationLabel = NSTextField(labelWithString: "00:00")

    init(audioURL: URL, metadata: DocumentMetadata) {
        self.audioURL = audioURL
        self.metadata = metadata
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Podcast"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        setupUI()
        setupPlayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        window?.delegate = self

        titleLabel.stringValue = metadata.title
        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = Date(timeIntervalSince1970: metadata.startTime)
        let end = Date(timeIntervalSince1970: metadata.endTime)
        timeLabel.stringValue = "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"
        timeLabel.textColor = .secondaryLabelColor

        summaryLabelField.font = NSFont.systemFont(ofSize: 12)
        summaryLabelField.lineBreakMode = .byWordWrapping
        summaryLabelField.maximumNumberOfLines = 0
        summaryLabelField.stringValue = metadata.summary

        transcriptLabelField.font = NSFont.systemFont(ofSize: 12)
        transcriptLabelField.lineBreakMode = .byWordWrapping
        transcriptLabelField.maximumNumberOfLines = 0
        transcriptLabelField.stringValue = sanitizedTranscript(metadata.formattedTranscript.isEmpty ? metadata.transcript : metadata.formattedTranscript)

        playButton.target = self
        playButton.action = #selector(togglePlay)
        playButton.bezelStyle = .texturedRounded
        playButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        seekSlider.target = self
        seekSlider.action = #selector(seekChanged)
        seekSlider.isContinuous = true

        currentTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .secondaryLabelColor
        durationLabel.textColor = .secondaryLabelColor

        let playRow = NSStackView(views: [playButton, currentTimeLabel, seekSlider, durationLabel])
        playRow.orientation = .horizontal
        playRow.alignment = .centerY
        playRow.spacing = 8
        playRow.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: "要約")
        summaryLabel.font = NSFont.boldSystemFont(ofSize: 12)
        let transcriptLabel = NSTextField(labelWithString: "文字起こし")
        transcriptLabel.font = NSFont.boldSystemFont(ofSize: 12)

        let stack = NSStackView(views: [
            titleLabel,
            timeLabel,
            playRow,
            summaryLabel,
            summaryLabelField,
            transcriptLabel,
            transcriptLabelField
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let scroll = NSScrollView()
        scroll.documentView = documentView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        background.addSubview(scroll)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: 20),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
            documentView.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            documentView.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            seekSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            summaryLabelField.widthAnchor.constraint(equalTo: documentView.widthAnchor),
            transcriptLabelField.widthAnchor.constraint(equalTo: documentView.widthAnchor)
        ])
    }

    private func setupPlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.prepareToPlay()
            if let duration = player?.duration {
                seekSlider.maxValue = duration
                durationLabel.stringValue = formatTime(duration)
            }
        } catch {
            AppLog.shared.add("Audio player failed: \(error.localizedDescription)")
        }
    }

    @objc private func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            playButton.title = "再生"
            stopTimer()
        } else {
            player.play()
            playButton.title = "停止"
            startTimer()
        }
    }

    @objc private func seekChanged() {
        guard let player else { return }
        player.currentTime = seekSlider.doubleValue
        currentTimeLabel.stringValue = formatTime(player.currentTime)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updatePlaybackUI()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updatePlaybackUI() {
        guard let player else { return }
        seekSlider.doubleValue = player.currentTime
        currentTimeLabel.stringValue = formatTime(player.currentTime)
        if !player.isPlaying {
            playButton.title = "再生"
            stopTimer()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func sanitizedTranscript(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "[BLANK_AUDIO]" }
        return lines.joined(separator: "\n")
    }
}

extension PlayerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        player?.stop()
        stopTimer()
    }
}
