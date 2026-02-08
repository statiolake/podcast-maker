import AVFoundation
import Combine
import Foundation

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
        title = metadata.title

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let start = Date(timeIntervalSince1970: metadata.startTime)
        let end = Date(timeIntervalSince1970: metadata.endTime)
        timeRange = "\(formatter.string(from: start)) 〜 \(formatter.string(from: end))"

        summary = metadata.summary
        transcript = PlayerViewModel.sanitizedTranscript(
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
        timer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: true)
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
