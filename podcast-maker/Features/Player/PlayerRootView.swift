import SwiftUI

struct PlayerRootView: View {
    @ObservedObject var viewModel: PlayerViewModel

    private enum Layout {
        static let outerPadding: CGFloat = 16
    }

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(viewModel.timeRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        .frame(alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { viewModel.currentTime },
                            set: { viewModel.seek(to: $0) }
                        ),
                        in: 0...max(viewModel.duration, 1)
                    )
                    .labelsHidden()
                    .disabled(!viewModel.canSeek)
                    .frame(maxWidth: .infinity)

                    Text(viewModel.durationText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(alignment: .leading)
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
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
    }
}

#if DEBUG
#Preview("Player") {
    let now = Date().timeIntervalSince1970
    let metadata = DocumentMetadata(
        title: "朝のメモ",
        startTime: now - 900,
        endTime: now - 120,
        summary: "散歩中に話した内容をまとめたサンプル要約です。",
        transcript: "今日は新しいUIの調整をして、次に収録フローの改善案を話しました。",
        formattedTranscript: """
        今日は新しいUIの調整をしました。
        次に、収録フローの改善案を話しました。
        """,
        topics: [],
        createdAt: now
    )
    let vm = PlayerViewModel(audioURL: URL(fileURLWithPath: "/tmp/preview-audio.wav"), metadata: metadata)
    vm.duration = 12 * 60 + 34
    vm.currentTime = 3 * 60 + 12
    return PlayerRootView(viewModel: vm)
        .frame(width: 760, height: 620)
}
#endif
