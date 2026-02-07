import Cocoa
import SwiftUI

final class DashboardWindowController: NSWindowController {
    private let viewModel: DashboardViewModel

    init(tracker: CostTracker,
         bedrock: BedrockService,
         onToggleRecording: @escaping () -> Void,
         onImport: @escaping () -> Void,
         onGenerateDocuments: @escaping () -> Void) {
        viewModel = DashboardViewModel(
            tracker: tracker,
            bedrock: bedrock,
            onToggleRecording: onToggleRecording,
            onImport: onImport,
            onGenerateDocuments: onGenerateDocuments
        )

        let rootView = DashboardRootView(viewModel: viewModel)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "PodcastMaker"
        window.minSize = NSSize(width: 1080, height: 700)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hosting

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func refresh() {
        viewModel.refreshAll()
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case recording
    case podcast
    case settings
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording: return "録音"
        case .podcast: return "Podcast"
        case .settings: return "設定"
        case .logs: return "ログ"
        }
    }

    var symbol: String {
        switch self {
        case .recording: return "waveform"
        case .podcast: return "music.note.house"
        case .settings: return "gearshape"
        case .logs: return "doc.plaintext"
        }
    }
}

struct DocumentRow: Identifiable {
    let id: URL
    let url: URL
    let displayTitle: String
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedSection: DashboardSection? = .recording
    @Published var isPaused = true
    @Published var transcriptLine = ""
    @Published var levels: [Float] = []
    @Published var documents: [DocumentRow] = []
    @Published var logs = ""

    @Published var awsProfile = ""
    @Published var bedrockStatus = "待機中"
    @Published var tokenSummary = ""
    @Published var modelPath = "未準備"
    @Published var modelState = "状態: 未準備"
    @Published var queueState = "待ちキュー: 0"
    @Published var downloadState = "ダウンロード: 停止"

    private let tracker: CostTracker
    private let bedrock: BedrockService
    private let onToggleRecording: () -> Void
    private let onImport: () -> Void
    private let onGenerateDocuments: () -> Void
    private let store = DocumentStore()

    private var playerWindow: PlayerWindowController?

    init(tracker: CostTracker,
         bedrock: BedrockService,
         onToggleRecording: @escaping () -> Void,
         onImport: @escaping () -> Void,
         onGenerateDocuments: @escaping () -> Void) {
        self.tracker = tracker
        self.bedrock = bedrock
        self.onToggleRecording = onToggleRecording
        self.onImport = onImport
        self.onGenerateDocuments = onGenerateDocuments

        NotificationCenter.default.addObserver(
            forName: .recordingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPaused = AppStateStore.shared.isPaused
        }

        NotificationCenter.default.addObserver(
            forName: .transcriptPreviewUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.transcriptLine = TranscriptPreviewStore.shared.lastLine()
        }

        NotificationCenter.default.addObserver(
            forName: .audioLevelUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.levels = AudioLevelStore.shared.snapshot()
        }

        NotificationCenter.default.addObserver(
            forName: .logUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logs = AppLog.shared.allText()
        }

        NotificationCenter.default.addObserver(
            forName: .queueUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshModelState()
        }

        refreshAll()
    }

    func refreshAll() {
        isPaused = AppStateStore.shared.isPaused
        transcriptLine = TranscriptPreviewStore.shared.lastLine()
        levels = AudioLevelStore.shared.snapshot()
        logs = AppLog.shared.allText()
        refreshDocuments()
        refreshSettingsSummary()
        refreshModelState()
    }

    func toggleRecording() {
        onToggleRecording()
    }

    func importAudio() {
        onImport()
    }

    func generatePodcast() {
        onGenerateDocuments()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshDocuments()
        }
    }

    func refreshDocuments() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        documents = store.recentDocuments(limit: 50).compactMap { folder in
            guard let metadata = store.loadMetadata(at: folder) else { return nil }
            let start = formatter.string(from: Date(timeIntervalSince1970: metadata.startTime))
            let end = formatter.string(from: Date(timeIntervalSince1970: metadata.endTime)).split(separator: " ").last ?? ""
            let title = "\(metadata.title) (\(start) 〜 \(end))"
            return DocumentRow(id: folder, url: folder, displayTitle: title)
        }
    }

    func openDocument(_ row: DocumentRow) {
        let audioURL = row.url.appendingPathComponent("audio.wav")
        guard let metadata = store.loadMetadata(at: row.url) else { return }
        playerWindow = PlayerWindowController(audioURL: audioURL, metadata: metadata)
        playerWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func saveProfile() {
        tracker.awsProfile = awsProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshSettingsSummary()
    }

    func testBedrock() {
        bedrockStatus = "接続中..."
        let profile = awsProfile
        Task {
            do {
                _ = try await bedrock.test(prompt: "Say hello in Japanese.", profile: profile)
                bedrockStatus = "接続成功"
                refreshSettingsSummary()
            } catch {
                bedrockStatus = "接続失敗: \(error.localizedDescription)"
            }
        }
    }

    func copyLogs() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(logs, forType: .string)
    }

    private func refreshSettingsSummary() {
        awsProfile = tracker.awsProfile
        tokenSummary = String(
            format: "入力 %lld / 出力 %lld / 推定コスト $%.4f",
            tracker.inputTokens,
            tracker.outputTokens,
            tracker.totalCostUSD()
        )
    }

    private func refreshModelState() {
        let status = WhisperASRWorker.shared.queueStatus()
        let progress = ModelManager.shared.status()
        modelPath = ModelManager.shared.modelPath() ?? "未準備"
        modelState = "状態: \(status.modelReady ? "準備完了" : "未準備")"
        queueState = "待ちキュー: \(status.pending)"
        if progress.expectedBytes > 0 {
            let percent = Int((Double(progress.downloadedBytes) / Double(progress.expectedBytes)) * 100.0)
            downloadState = "ダウンロード: \(percent)%"
        } else {
            downloadState = "ダウンロード: \(progress.downloading ? "進行中" : "停止")"
        }
    }
}

struct DashboardRootView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 4)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270)
        } detail: {
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
        .frame(minWidth: 1080, minHeight: 700)
    }
}

struct RecordingDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("録音")
                .font(.system(size: 30, weight: .bold))

            Text(viewModel.isPaused ? "現在: 一時停止中" : "現在: 録音中")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(viewModel.isPaused ? "録音開始" : "一時停止") {
                    viewModel.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("音声ファイルをインポート...") {
                    viewModel.importAudio()
                }
                .buttonStyle(.bordered)
            }

            WaveformCanvas(levels: viewModel.levels)
                .frame(height: 250)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }

            Text(viewModel.transcriptLine.isEmpty ? "..." : viewModel.transcriptLine)
                .font(.system(size: 18, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }

            Spacer()
        }
        .padding(28)
    }
}

struct WaveformCanvas: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            guard levels.count > 1 else { return }

            let midY = size.height / 2
            let step = size.width / CGFloat(max(1, levels.count - 1))

            var top = Path()
            var bottom = Path()

            for (idx, level) in levels.enumerated() {
                let x = CGFloat(idx) * step
                let amp = CGFloat(min(1.0, level * 7.0)) * (size.height * 0.42)
                let yTop = midY + amp
                let yBottom = midY - amp

                if idx == 0 {
                    top.move(to: CGPoint(x: x, y: yTop))
                    bottom.move(to: CGPoint(x: x, y: yBottom))
                } else {
                    top.addLine(to: CGPoint(x: x, y: yTop))
                    bottom.addLine(to: CGPoint(x: x, y: yBottom))
                }
            }

            let stroke = Color.accentColor.opacity(0.9)
            context.stroke(top, with: .color(stroke), lineWidth: 2)
            context.stroke(bottom, with: .color(stroke), lineWidth: 2)
        }
    }
}

struct PodcastDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Podcast")
                .font(.system(size: 30, weight: .bold))

            Button("Podcast を作成（直近3時間）") {
                viewModel.generatePodcast()
            }
            .buttonStyle(.borderedProminent)

            List(viewModel.documents) { row in
                Text(row.displayTitle)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        viewModel.openDocument(row)
                    }
            }
            .listStyle(.inset)
        }
        .padding(28)
    }
}

struct SettingsDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("設定")
                    .font(.system(size: 30, weight: .bold))

                GroupBox("Bedrock") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AWS_PROFILE")
                            .font(.system(size: 12, weight: .medium))
                        TextField("default", text: $viewModel.awsProfile)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                viewModel.saveProfile()
                            }
                        Text(viewModel.bedrockStatus)
                            .foregroundStyle(.secondary)
                        Text(viewModel.tokenSummary)
                            .foregroundStyle(.secondary)
                        Button("接続テスト") {
                            viewModel.testBedrock()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Whisper モデル") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("パス: \(viewModel.modelPath)")
                        Text(viewModel.modelState)
                        Text(viewModel.queueState)
                        Text(viewModel.downloadState)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(28)
        }
    }
}

struct LogsDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ログ")
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                Button {
                    viewModel.copyLogs()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(viewModel.logs)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .padding(28)
    }
}

final class AppStateStore {
    static let shared = AppStateStore()
    private let queue = DispatchQueue(label: "app.state")
    private var paused = true

    private init() {}

    func setPaused(_ value: Bool) {
        queue.async {
            self.paused = value
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .recordingStateChanged, object: nil)
            }
        }
    }

    var isPaused: Bool {
        queue.sync { paused }
    }
}
