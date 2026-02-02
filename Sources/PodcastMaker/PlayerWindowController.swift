import Cocoa
import AVFoundation

final class PlayerWindowController: NSWindowController {
    private let audioURL: URL
    private let metadata: DocumentMetadata
    private var player: AVAudioPlayer?

    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let summaryView = NSTextView()
    private let playButton = NSButton(title: "再生", target: nil, action: nil)

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

        summaryView.isEditable = false
        summaryView.isSelectable = true
        summaryView.font = NSFont.systemFont(ofSize: 12)
        summaryView.string = metadata.summary

        playButton.target = self
        playButton.action = #selector(togglePlay)

        let scroll = NSScrollView()
        scroll.documentView = summaryView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, timeLabel, playButton, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            scroll.heightAnchor.constraint(equalToConstant: 220)
        ])
    }

    private func setupPlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.prepareToPlay()
        } catch {
            AppLog.shared.add("Audio player failed: \(error.localizedDescription)")
        }
    }

    @objc private func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            playButton.title = "再生"
        } else {
            player.play()
            playButton.title = "停止"
        }
    }
}
