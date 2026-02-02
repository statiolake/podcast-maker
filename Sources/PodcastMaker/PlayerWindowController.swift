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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "完成品"
        super.init(window: window)
        setupUI()
        setupPlayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        titleLabel.stringValue = metadata.title
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)

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

        seekSlider.target = self
        seekSlider.action = #selector(seekChanged)
        seekSlider.isContinuous = true

        currentTimeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        currentTimeLabel.textColor = .secondaryLabelColor
        durationLabel.textColor = .secondaryLabelColor

        let timeRow = NSStackView(views: [currentTimeLabel, seekSlider, durationLabel])
        timeRow.orientation = .horizontal
        timeRow.alignment = .centerY
        timeRow.spacing = 8
        timeRow.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: "要約")
        summaryLabel.font = NSFont.boldSystemFont(ofSize: 12)
        let transcriptLabel = NSTextField(labelWithString: "文字起こし")
        transcriptLabel.font = NSFont.boldSystemFont(ofSize: 12)

        let stack = NSStackView(views: [
            titleLabel,
            timeLabel,
            playButton,
            timeRow,
            summaryLabel,
            summaryLabelField,
            transcriptLabel,
            transcriptLabelField
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            seekSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            summaryLabelField.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            transcriptLabelField.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
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
