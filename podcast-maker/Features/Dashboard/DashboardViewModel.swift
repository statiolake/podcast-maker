import AppKit
import Combine
import Foundation

@MainActor
protocol DashboardViewModeling: ObservableObject {
    var selectedSection: DashboardSection? { get set }
    var isPaused: Bool { get set }
    var transcriptLine: String { get set }
    var transcriptPreviewLines: [String] { get set }
    var levels: [Float] { get set }
    var documents: [DocumentRow] { get set }
    var logs: String { get set }
    var awsProfile: String { get set }
    var availableProfiles: [String] { get set }
    var profileSourcePath: String { get set }
    var bedrockStatus: String { get set }
    var tokenSummary: String { get set }
    var modelPath: String { get set }
    var modelState: String { get set }
    var queueState: String { get set }

    func refreshAll()
    func toggleRecording()
    func importAudio()
    func generatePodcast()
    func saveProfile()
    func reloadProfiles()
    func testBedrock()
    func copyLogs()
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var selectedSection: DashboardSection? = .recording
    @Published var isPaused = true
    @Published var transcriptLine = ""
    @Published var transcriptPreviewLines: [String] = []
    @Published var levels: [Float] = []
    @Published var documents: [DocumentRow] = []
    @Published var logs = ""

    @Published var awsProfile = ""
    @Published var availableProfiles: [String] = []
    @Published var profileSourcePath = ""
    @Published var bedrockStatus = "待機中"
    @Published var tokenSummary = ""
    @Published var modelPath = "未準備"
    @Published var modelState = "未準備"
    @Published var queueState = "0"

    private let tracker: CostTracker
    private let bedrock: BedrockService
    private let onToggleRecording: () -> Void
    private let onImport: () -> Void
    private let onGenerateDocuments: () -> Void
    private let store = DocumentStore()

    init(
        tracker: CostTracker,
        bedrock: BedrockService,
        onToggleRecording: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onGenerateDocuments: @escaping () -> Void
    ) {
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
            self?.transcriptPreviewLines = TranscriptPreviewStore.shared.recentLines(limit: 3)
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
        reloadProfiles()
        isPaused = AppStateStore.shared.isPaused
        transcriptLine = TranscriptPreviewStore.shared.lastLine()
        transcriptPreviewLines = TranscriptPreviewStore.shared.recentLines(limit: 3)
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

    func reloadProfiles() {
        let loaded = AWSProfileCatalog.loadProfiles()
        availableProfiles = loaded
        profileSourcePath = AWSProfileCatalog.configPath

        let persisted = tracker.awsProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persisted.isEmpty, loaded.contains(persisted) {
            awsProfile = persisted
        } else {
            awsProfile = loaded.first ?? "default"
            tracker.awsProfile = awsProfile
        }
    }

    func testBedrock() {
        bedrockStatus = "接続中..."
        let profile = awsProfile
        let service = bedrock

        Task {
            do {
                _ = try await service.test(prompt: "Say hello in Japanese.", profile: profile)
                await MainActor.run {
                    self.bedrockStatus = "接続成功"
                    self.refreshSettingsSummary()
                }
            } catch {
                await MainActor.run {
                    self.bedrockStatus = "接続失敗: \(error.localizedDescription)"
                }
            }
        }
    }

    func copyLogs() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(logs, forType: .string)
    }

    private func refreshSettingsSummary() {
        let persisted = tracker.awsProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        if persisted.isEmpty {
            if awsProfile.isEmpty {
                awsProfile = "default"
            }
            tracker.awsProfile = awsProfile
        } else {
            awsProfile = persisted
        }
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
        queueState = "\(status.pending)"

        if progress.expectedBytes > 0 {
            let percent = Int((Double(progress.downloadedBytes) / Double(progress.expectedBytes)) * 100.0)
            modelState = "ダウンロード中 \(percent)%"
        } else if progress.downloading {
            modelState = "ダウンロード中"
        } else {
            modelState = status.modelReady ? "準備完了" : "未準備"
        }
    }
}

extension DashboardViewModel: DashboardViewModeling {}
