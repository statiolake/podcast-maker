import Cocoa
import AVFoundation
import SwiftUI

final class PlayerWindowController: NSWindowController {
    private let viewModel: PlayerViewModel

    init(audioURL: URL, metadata: DocumentMetadata) {
        viewModel = PlayerViewModel(audioURL: audioURL, metadata: metadata)
        let rootView = PlayerRootView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Podcast"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 680, height: 520)
        window.contentViewController = hosting

        super.init(window: window)
        window.delegate = self
        viewModel.preparePlayer()
    }

    required init?(coder: NSCoder) {
        return nil
    }
}

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    let title: String
    let timeRange: String
    let summary: String
    let transcript: String

    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private let audioURL: URL
    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(audioURL: URL, metadata: DocumentMetadata) {
        self.audioURL = audioURL
        self.title = metadata.title

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = Date(timeIntervalSince1970: metadata.startTime)
        let end = Date(timeIntervalSince1970: metadata.endTime)
        self.timeRange = "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"

        self.summary = metadata.summary
        self.transcript = PlayerViewModel.sanitizedTranscript(
            metadata.formattedTranscript.isEmpty ? metadata.transcript : metadata.formattedTranscript
        )
    }

    func preparePlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
        } catch {
            AppLog.shared.add("Audio player failed: \(error.localizedDescription)")
        }
    }

    func togglePlay() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to value: Double) {
        guard let player else { return }
        player.currentTime = value
        currentTime = value
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    var currentTimeText: String {
        Self.formatTime(currentTime)
    }

    var durationText: String {
        Self.formatTime(duration)
    }

    var canSeek: Bool {
        duration > 0
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(timeInterval: 0.2,
                                     target: self,
                                     selector: #selector(handleTimer),
                                     userInfo: nil,
                                     repeats: true)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleTimer() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            stopTimer()
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private static func sanitizedTranscript(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "[BLANK_AUDIO]" }
            .joined(separator: "\n")
    }
}

struct PlayerRootView: View {
    @ObservedObject var viewModel: PlayerViewModel

    private enum Layout {
        static let outerPadding: CGFloat = 16
        // Form has built-in system insets; we counter with negative padding.
        static let formHorizontalTrim: CGFloat = 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(viewModel.timeRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section {
                    HStack(spacing: 8) {
                        Button {
                            viewModel.togglePlay()
                        } label: {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .help(viewModel.isPlaying ? "一時停止" : "再生")

                        Text(viewModel.currentTimeText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { viewModel.currentTime },
                                set: { viewModel.seek(to: $0) }
                            ),
                            in: 0...max(viewModel.duration, 1)
                        )
                        .disabled(!viewModel.canSeek)
                        .frame(maxWidth: .infinity)

                        Text(viewModel.durationText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("要約") {
                    Text(viewModel.summary.isEmpty ? "（要約なし）" : viewModel.summary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("文字起こし") {
                    if viewModel.transcript.isEmpty {
                        Text("（文字起こしなし）")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.transcript)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.top, 0)
            .padding(.horizontal, -Layout.formHorizontalTrim)
        }
        .padding(Layout.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PlayerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        viewModel.stop()
    }
}
