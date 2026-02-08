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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "dashboard-toolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.minSize = NSSize(width: 1080, height: 700)
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
    let metadata: DocumentMetadata

    var audioURL: URL {
        url.appendingPathComponent("audio.wav")
    }
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
            Task { @MainActor [weak self] in
                self?.isPaused = AppStateStore.shared.isPaused
            }
        }

        NotificationCenter.default.addObserver(
            forName: .transcriptPreviewUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.transcriptLine = TranscriptPreviewStore.shared.lastLine()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .audioLevelUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.levels = AudioLevelStore.shared.snapshot()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .logUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logs = AppLog.shared.allText()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .queueUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshModelState()
            }
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
            return DocumentRow(id: folder, url: folder, displayTitle: title, metadata: metadata)
        }
    }

    func saveProfile() {
        tracker.awsProfile = awsProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshSettingsSummary()
    }

    func testBedrock() {
        bedrockStatus = "接続中..."
        let profile = awsProfile
        Task { @MainActor in
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

struct RecordingDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("録音")
                    .font(.largeTitle)
                Spacer()
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

            GroupBox("状態") {
                LabeledContent("録音") {
                    Text(viewModel.isPaused ? "一時停止中" : "録音中")
                }
                LabeledContent("ライブ文字起こし") {
                    Text(viewModel.transcriptLine.isEmpty ? "待機中" : viewModel.transcriptLine)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(viewModel.transcriptLine.isEmpty ? .secondary : .primary)
                }
            }

            GroupBox("入力レベル") {
                WaveformCanvas(levels: viewModel.levels)
                    .frame(height: 220)
            }

            Spacer()
        }
        .padding(24)
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

            context.stroke(top, with: .color(.accentColor), lineWidth: 2)
            context.stroke(bottom, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

struct PodcastDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
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

        self.selection = viewModel.documents[0].id
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

struct SettingsDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section("Amazon Bedrock") {
                LabeledContent("AWS Profile") {
                    HStack(spacing: 8) {
                        TextField("default", text: $viewModel.awsProfile)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        Button("保存") {
                            viewModel.saveProfile()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent("接続状態") {
                    Text(viewModel.bedrockStatus)
                }

                LabeledContent("トークン使用量") {
                    Text(viewModel.tokenSummary)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Spacer()
                    Button("接続テスト") {
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
                LabeledContent("ダウンロード") {
                    Text(viewModel.downloadState)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

struct LogsDashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

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

extension AppStateStore: @unchecked Sendable {}
