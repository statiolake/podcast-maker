import Combine
import SwiftUI

struct DashboardRootView<ViewModel: DashboardViewModeling>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(DashboardSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("PodcastMaker")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 1080, minHeight: 700)
    }

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.selectedSection ?? .recording {
        case .recording:
            RecordingDashboardView(viewModel: viewModel)
        case .podcast:
            PodcastDashboardView(viewModel: viewModel)
        case .settings:
            SettingsDashboardView(viewModel: viewModel)
        case .logs:
            LogsDashboardView(viewModel: viewModel)
        }
    }
}

struct RecordingDashboardView<ViewModel: DashboardViewModeling>: View {
    @ObservedObject var viewModel: ViewModel

    private var liveCaption: String {
        let trimmed = viewModel.transcriptLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "話すとここにライブ字幕が表示されます"
        }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("録音")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("マイク入力をリアルタイムで文字起こしします")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("音声ファイルをインポート...") {
                    viewModel.importAudio()
                }
                .buttonStyle(.bordered)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)

                WaveformCanvas(levels: viewModel.levels)
                    .opacity(viewModel.isPaused ? 0.28 : 0.58)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 20) {
                    Spacer()

                    Button {
                        viewModel.toggleRecording()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: viewModel.isPaused ? "record.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 46, weight: .semibold))
                            Text(viewModel.isPaused ? "録音開始" : "一時停止")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 156, height: 156)
                        .background(
                            Circle()
                                .fill(viewModel.isPaused ? Color.gray.gradient : Color.red.gradient)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isPaused ? "録音開始" : "一時停止")

                    Text(liveCaption)
                        .font(.title3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.horizontal, 42)
                        .contentTransition(.opacity)

                    Spacer()
                }
                .padding(22)
            }
            .frame(minHeight: 310, maxHeight: .infinity)
        }
        .padding(24)
    }
}

struct WaveformCanvas: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                },
                with: .color(.secondary.opacity(0.18)),
                lineWidth: 1
            )

            let points = mirroredPoints(in: size)
            guard points.top.count > 1 else { return }

            context.stroke(smoothPath(points: points.top), with: .color(.accentColor), lineWidth: 2)
            context.stroke(smoothPath(points: points.bottom), with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func mirroredPoints(in size: CGSize) -> (top: [CGPoint], bottom: [CGPoint]) {
        guard !levels.isEmpty else { return ([], []) }

        let desiredSpacing: CGFloat = 5.5
        let slotCount = max(2, Int(size.width / desiredSpacing))
        let step = size.width / CGFloat(slotCount - 1)
        let recent = Array(levels.suffix(slotCount))
        let startX = size.width - CGFloat(max(0, recent.count - 1)) * step
        let midY = size.height / 2

        let points: [(CGPoint, CGPoint)] = recent.enumerated().map { idx, level in
            let x = startX + CGFloat(idx) * step
            let normalized = CGFloat(min(1.0, max(0.0, level * 7.0)))
            let smoothed = pow(normalized, 0.72)
            let amplitude = smoothed * (size.height * 0.42)
            return (
                CGPoint(x: x, y: midY + amplitude),
                CGPoint(x: x, y: midY - amplitude)
            )
        }

        return (points.map(\.0), points.map(\.1))
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 1 else { return path }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: mid, control: previous)

            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }

        return path
    }
}

struct PodcastDashboardView<ViewModel: DashboardViewModeling>: View {
    @ObservedObject var viewModel: ViewModel
    @State private var selection: URL?
    @State private var playerViewModel: PlayerViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Podcast")
                    .font(.largeTitle)
                Spacer()
                Button("Podcast を作成（直近3時間）") {
                    viewModel.generatePodcast()
                }
                .buttonStyle(.borderedProminent)
            }

            HSplitView {
                if viewModel.documents.isEmpty {
                    ContentUnavailableView("まだPodcastがありません", systemImage: "music.note")
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(viewModel.documents, selection: $selection) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.metadata.title)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(row.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(row.id)
                    }
                    .listStyle(.inset)
                    .frame(minWidth: 290, idealWidth: 320, maxWidth: 360)
                }

                if let playerViewModel {
                    PlayerRootView(viewModel: playerViewModel)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Podcastを選択してください", systemImage: "play.square")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(24)
        .onAppear {
            syncSelectionWithDocuments()
        }
        .onDisappear {
            playerViewModel?.stop()
        }
        .onChange(of: viewModel.documents.map(\.id)) {
            syncSelectionWithDocuments()
        }
        .onChange(of: selection) {
            rebuildPlayer()
        }
    }

    private func syncSelectionWithDocuments() {
        guard !viewModel.documents.isEmpty else {
            playerViewModel?.stop()
            playerViewModel = nil
            selection = nil
            return
        }

        if let selection, viewModel.documents.contains(where: { $0.id == selection }) {
            rebuildPlayer()
            return
        }

        selection = viewModel.documents[0].id
        rebuildPlayer()
    }

    private func rebuildPlayer() {
        guard let selection,
              let row = viewModel.documents.first(where: { $0.id == selection }) else {
            playerViewModel?.stop()
            playerViewModel = nil
            return
        }

        playerViewModel?.stop()
        let model = PlayerViewModel(audioURL: row.audioURL, metadata: row.metadata)
        model.preparePlayer()
        playerViewModel = model
    }
}

struct SettingsDashboardView<ViewModel: DashboardViewModeling>: View {
    @ObservedObject var viewModel: ViewModel
    @State private var showConnectionFailure = false
    @State private var connectionFailureMessage = ""

    private var connectionTestTitle: String {
        if viewModel.bedrockStatus.hasPrefix("接続中") {
            return "テスト中..."
        }
        return viewModel.bedrockStatus.hasPrefix("接続成功") ? "接続完了" : "接続テスト"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("設定").font(.largeTitle)
            Form {
                Section("Amazon Bedrock") {
                    LabeledContent("AWS Profile") {
                        HStack(spacing: 4) {
                            Picker("AWS Profile", selection: $viewModel.awsProfile) {
                                ForEach(viewModel.availableProfiles, id: \.self) { profile in
                                    Text(profile).tag(profile)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .onChange(of: viewModel.awsProfile) {
                                viewModel.saveProfile()
                            }

                            Button {
                                viewModel.reloadProfiles()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .help("AWS Profile を再読み込み")
                        }
                    }

                    LabeledContent("設定ファイル") {
                        Text(viewModel.profileSourcePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    LabeledContent("トークン使用量") {
                        Text(viewModel.tokenSummary)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Spacer()
                        Button(connectionTestTitle) {
                            viewModel.testBedrock()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("Whisper") {
                    LabeledContent("モデルパス") {
                        Text(viewModel.modelPath)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                    LabeledContent("モデル状態") {
                        Text(viewModel.modelState)
                    }
                    LabeledContent("待ちキュー") {
                        Text(viewModel.queueState)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                viewModel.reloadProfiles()
            }
            .onChange(of: viewModel.bedrockStatus) {
                let prefix = "接続失敗:"
                if viewModel.bedrockStatus.hasPrefix(prefix) {
                    connectionFailureMessage = String(viewModel.bedrockStatus.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if connectionFailureMessage.isEmpty {
                        connectionFailureMessage = "Bedrock への接続に失敗しました。"
                    }
                    showConnectionFailure = true
                }
            }
            .alert("接続失敗", isPresented: $showConnectionFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(connectionFailureMessage)
            }
        }
        .padding(24)
    }
}

struct LogsDashboardView<ViewModel: DashboardViewModeling>: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ログ")
                    .font(.largeTitle)
                Spacer()
                Button("コピー") {
                    viewModel.copyLogs()
                }
                .buttonStyle(.bordered)
            }

            GroupBox {
                ScrollView {
                    Text(viewModel.logs)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }
}

#if DEBUG
@MainActor
private enum DashboardPreviewFactory {
    static func makeViewModel() -> PreviewDashboardViewModel {
        let viewModel = PreviewDashboardViewModel()

        let now = Date().timeIntervalSince1970
        let topic = TopicSegment(
            title: "収録テスト",
            startTime: now - 1800,
            endTime: now - 900,
            summary: "収録フローの確認と改善ポイントの整理。",
            formattedTranscript: "収録フローの確認と改善ポイントを整理しました。"
        )
        let metadataA = DocumentMetadata(
            title: "朝の収録",
            startTime: now - 3600,
            endTime: now - 1800,
            summary: "朝の収録内容の要約サンプルです。",
            transcript: "朝の収録内容です。",
            formattedTranscript: "朝の収録内容です。",
            topics: [topic],
            createdAt: now - 1700
        )
        let metadataB = DocumentMetadata(
            title: "午後のメモ",
            startTime: now - 1500,
            endTime: now - 600,
            summary: "午後に話したメモをまとめたサンプルです。",
            transcript: "午後のメモです。",
            formattedTranscript: "午後のメモです。",
            topics: [topic],
            createdAt: now - 500
        )

        let urlA = URL(fileURLWithPath: "/tmp/preview-podcast-a")
        let urlB = URL(fileURLWithPath: "/tmp/preview-podcast-b")
        viewModel.documents = [
            DocumentRow(id: urlA, url: urlA, displayTitle: "朝の収録 (2026/02/08 09:00 〜 09:30)", metadata: metadataA),
            DocumentRow(id: urlB, url: urlB, displayTitle: "午後のメモ (2026/02/08 13:10 〜 13:25)", metadata: metadataB)
        ]

        viewModel.isPaused = false
        viewModel.transcriptLine = "この行はライブ文字起こしのプレビューです。"
        viewModel.transcriptPreviewLines = [
            "この行はライブ文字起こしのプレビューです。",
            "いま録音ページのデザインを確認しています。",
            "音声入力は正常です。"
        ]
        viewModel.levels = [0.02, 0.06, 0.11, 0.18, 0.09, 0.04, 0.14, 0.08, 0.03]
        viewModel.logs = """
[12:10:15] App launched
[12:10:20] Audio engine started
[12:10:22] Transcript saved id=preview
"""
        viewModel.bedrockStatus = "接続成功"
        viewModel.tokenSummary = "入力 420 / 出力 188 / 推定コスト $0.0042"
        viewModel.availableProfiles = ["default", "dev", "prod"]
        viewModel.awsProfile = "default"
        viewModel.profileSourcePath = "~/.aws/config"
        viewModel.modelPath = "/Users/dicen/Library/Application Support/PodcastMaker/models/ggml-small.bin"
        viewModel.modelState = "準備完了"
        viewModel.queueState = "1"

        return viewModel
    }
}

@MainActor
private final class PreviewDashboardViewModel: DashboardViewModeling {
    @Published var selectedSection: DashboardSection? = .recording
    @Published var isPaused = true
    @Published var transcriptLine = ""
    @Published var transcriptPreviewLines: [String] = []
    @Published var levels: [Float] = []
    @Published var documents: [DocumentRow] = []
    @Published var logs = ""
    @Published var awsProfile = "default"
    @Published var availableProfiles: [String] = ["default"]
    @Published var profileSourcePath = "~/.aws/config"
    @Published var bedrockStatus = "待機中"
    @Published var tokenSummary = ""
    @Published var modelPath = "未準備"
    @Published var modelState = "未準備"
    @Published var queueState = "0"

    func refreshAll() {}
    func toggleRecording() { isPaused.toggle() }
    func importAudio() {}
    func generatePodcast() {}
    func saveProfile() {}
    func reloadProfiles() {}
    func testBedrock() { bedrockStatus = "プレビュー: 接続テストは無効" }
    func copyLogs() {}
}

#Preview("Dashboard / Root") {
    let vm = DashboardPreviewFactory.makeViewModel()
    vm.selectedSection = .recording
    return DashboardRootView(viewModel: vm)
        .frame(width: 1240, height: 820)
}

#Preview("Dashboard / Recording") {
    RecordingDashboardView(viewModel: DashboardPreviewFactory.makeViewModel())
        .frame(width: 980, height: 680)
}

#Preview("Dashboard / Podcast") {
    PodcastDashboardView(viewModel: DashboardPreviewFactory.makeViewModel())
        .frame(width: 1100, height: 700)
}

#Preview("Dashboard / Settings") {
    SettingsDashboardView(viewModel: DashboardPreviewFactory.makeViewModel())
        .frame(width: 980, height: 680)
}

#Preview("Dashboard / Logs") {
    LogsDashboardView(viewModel: DashboardPreviewFactory.makeViewModel())
        .frame(width: 980, height: 680)
}

#Preview("Dashboard / Waveform") {
    WaveformCanvas(levels: [0.01, 0.08, 0.03, 0.15, 0.06, 0.12, 0.04, 0.02, 0.11])
        .frame(width: 720, height: 220)
        .padding(24)
}
#endif
