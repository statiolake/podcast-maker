import Cocoa

final class DashboardWindowController: NSWindowController {
    private let tabController = NSTabViewController()

    init(tracker: CostTracker,
         bedrock: BedrockService,
         pipeline: AudioPipeline,
         importer: AudioImporter,
         onToggleRecording: @escaping () -> Void,
         onImport: @escaping () -> Void,
         onGenerateDocuments: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "PodcastMaker"
        window.titleVisibility = .visible
        super.init(window: window)

        tabController.tabStyle = .toolbar

        let recordingVC = RecordingViewController(onToggleRecording: onToggleRecording,
                                                  onImport: onImport)
        recordingVC.title = "録音"

        let podcastVC = PodcastViewController(onGenerateDocuments: onGenerateDocuments)
        podcastVC.title = "Podcast"

        let settingsVC = SettingsViewController(tracker: tracker, bedrock: bedrock)
        settingsVC.title = "設定"

        let logsVC = LogsViewController()
        logsVC.title = "ログ"

        tabController.addChild(recordingVC)
        tabController.addChild(podcastVC)
        tabController.addChild(settingsVC)
        tabController.addChild(logsVC)

        window.contentViewController = tabController
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func refresh() {
        for child in tabController.children {
            if let refreshable = child as? DashboardRefreshable {
                refreshable.refresh()
            }
        }
    }
}

protocol DashboardRefreshable {
    func refresh()
}

final class RecordingViewController: NSViewController, DashboardRefreshable {
    private let onToggleRecording: () -> Void
    private let onImport: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private let toggleButton = NSButton(title: "録音開始", target: nil, action: nil)
    private let importButton = NSButton(title: "音声ファイルをインポート...", target: nil, action: nil)
    private let previewTextView = NSTextView()

    init(onToggleRecording: @escaping () -> Void, onImport: @escaping () -> Void) {
        self.onToggleRecording = onToggleRecording
        self.onImport = onImport
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        toggleButton.bezelStyle = .rounded
        toggleButton.target = self
        toggleButton.action = #selector(toggleRecording)

        importButton.bezelStyle = .rounded
        importButton.target = self
        importButton.action = #selector(importAudio)

        let buttonRow = NSStackView(views: [toggleButton, importButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.font = NSFont.systemFont(ofSize: 12)
        previewTextView.string = TranscriptPreviewStore.shared.allText()

        let scroll = NSScrollView()
        scroll.documentView = previewTextView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "リアルタイム文字起こし")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)

        let stack = NSStackView(views: [statusLabel, buttonRow, titleLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(updateRecordingState), name: .recordingStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshPreview), name: .transcriptPreviewUpdated, object: nil)
        updateRecordingState()
    }

    @objc private func toggleRecording() {
        onToggleRecording()
    }

    @objc private func importAudio() {
        onImport()
    }

    @objc private func updateRecordingState() {
        let paused = AppStateStore.shared.isPaused
        statusLabel.stringValue = paused ? "状態: 停止中" : "状態: 録音中"
        toggleButton.title = paused ? "録音開始" : "録音停止"
    }

    @objc private func refreshPreview() {
        previewTextView.string = TranscriptPreviewStore.shared.allText()
        previewTextView.scrollToEndOfDocument(nil)
    }

    func refresh() {
        updateRecordingState()
        refreshPreview()
    }
}

final class PodcastViewController: NSViewController, DashboardRefreshable, NSTableViewDataSource, NSTableViewDelegate {
    private let onGenerateDocuments: () -> Void
    private let store = DocumentStore()
    private var documents: [URL] = []
    private let tableView = NSTableView()

    init(onGenerateDocuments: @escaping () -> Void) {
        self.onGenerateDocuments = onGenerateDocuments
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        let generateButton = NSButton(title: "Podcast を作成（直近3時間）", target: self, action: #selector(generateDocuments))
        generateButton.bezelStyle = .rounded

        let header = NSTextField(labelWithString: "過去のPodcast")
        header.font = NSFont.boldSystemFont(ofSize: 13)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "タイトル"
        column.width = 600
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 28
        tableView.target = self
        tableView.doubleAction = #selector(openSelected)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [generateButton, header, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])

        refresh()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        documents.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let textField = NSTextField(labelWithString: titleForDocument(documents[row]))
        textField.lineBreakMode = .byTruncatingTail
        cell.addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func generateDocuments() {
        onGenerateDocuments()
    }

    @objc private func openSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < documents.count else { return }
        openDocument(documents[row])
    }

    private func openDocument(_ folder: URL) {
        let audioURL = folder.appendingPathComponent("audio.wav")
        guard let metadata = store.loadMetadata(at: folder) else { return }
        let player = PlayerWindowController(audioURL: audioURL, metadata: metadata)
        player.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func titleForDocument(_ folder: URL) -> String {
        if let metadata = store.loadMetadata(at: folder) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
            let start = Date(timeIntervalSince1970: metadata.startTime)
            let end = Date(timeIntervalSince1970: metadata.endTime)
            let startStr = formatter.string(from: start)
            let endStr = formatter.string(from: end)
            let endTime = endStr.split(separator: " ").last ?? Substring("")
            return "\(metadata.title) (\(startStr) 〜 \(endTime))"
        }
        return folder.lastPathComponent
    }

    func refresh() {
        documents = store.recentDocuments(limit: 30)
        tableView.reloadData()
    }
}

final class SettingsViewController: NSViewController, DashboardRefreshable, NSTextFieldDelegate {
    private let tracker: CostTracker
    private let bedrock: BedrockService

    private let awsField = NSTextField(string: "")
    private let inputTokensLabel = NSTextField(labelWithString: "")
    private let outputTokensLabel = NSTextField(labelWithString: "")
    private let cacheTokensLabel = NSTextField(labelWithString: "")
    private let totalCostLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Bedrock ステータス: 待機中")
    private let testButton = NSButton(title: "Bedrock テスト", target: nil, action: nil)
    private let modelPathLabel = NSTextField(labelWithString: "")
    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let downloadStatusLabel = NSTextField(labelWithString: "")
    private let downloadProgressLabel = NSTextField(labelWithString: "")
    private let queueStatusLabel = NSTextField(labelWithString: "")

    init(tracker: CostTracker, bedrock: BedrockService) {
        self.tracker = tracker
        self.bedrock = bedrock
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "Bedrock（Claude Haiku 4.5）")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)

        let modelLabel = NSTextField(labelWithString: "モデル: \(HaikuPricing.modelId)")
        modelLabel.font = NSFont.systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        testButton.target = self
        testButton.action = #selector(runBedrockTest)

        let awsLabel = NSTextField(labelWithString: "AWS_PROFILE")
        awsField.placeholderString = "default"
        awsField.delegate = self

        let tokensTitle = NSTextField(labelWithString: "トークン使用量")
        tokensTitle.font = NSFont.boldSystemFont(ofSize: 12)

        let modelTitle = NSTextField(labelWithString: "Whisper モデル")
        modelTitle.font = NSFont.boldSystemFont(ofSize: 12)

        let stack = NSStackView(views: [
            titleLabel,
            modelLabel,
            awsLabel,
            awsField,
            tokensTitle,
            inputTokensLabel,
            outputTokensLabel,
            cacheTokensLabel,
            totalCostLabel,
            statusLabel,
            testButton,
            modelTitle,
            modelPathLabel,
            modelStatusLabel,
            downloadStatusLabel,
            downloadProgressLabel,
            queueStatusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refreshQueue), name: .queueUpdated, object: nil)
        refresh()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        tracker.awsProfile = awsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refresh() {
        awsField.stringValue = tracker.awsProfile
        inputTokensLabel.stringValue = "入力トークン: \(tracker.inputTokens)"
        outputTokensLabel.stringValue = "出力トークン: \(tracker.outputTokens)"
        cacheTokensLabel.stringValue = "キャッシュトークン (5m/1h/hit): \(tracker.cacheWrite5mTokens) / \(tracker.cacheWrite1hTokens) / \(tracker.cacheHitTokens)"
        totalCostLabel.stringValue = String(format: "推定コスト合計: $%.4f", tracker.totalCostUSD())
        refreshQueue()
    }

    @objc private func runBedrockTest() {
        testButton.isEnabled = false
        statusLabel.stringValue = "Bedrock ステータス: 実行中..."

        let profile = tracker.awsProfile
        let prompt = "Return a single short sentence saying hello."

        Task {
            do {
                _ = try await bedrock.test(prompt: prompt, profile: profile)
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                    self?.statusLabel.stringValue = "Bedrock ステータス: 成功"
                    self?.testButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    AppLog.shared.add("Bedrock test failed: \(error.localizedDescription)")
                    self?.statusLabel.stringValue = "Bedrock ステータス: 失敗"
                    self?.testButton.isEnabled = true
                }
            }
        }
    }

    @objc private func refreshQueue() {
        let status = WhisperASRWorker.shared.queueStatus()
        let progress = ModelManager.shared.status()
        let modelPath = ModelManager.shared.modelPath() ?? "未準備"
        modelPathLabel.stringValue = "パス: \(modelPath)"
        modelStatusLabel.stringValue = "モデル: \(status.modelReady ? "準備完了" : "未準備")"
        downloadStatusLabel.stringValue = "ダウンロード: \(status.downloading ? "進行中" : "停止")"
        queueStatusLabel.stringValue = "保留中セグメント: \(status.pending)"
        if progress.expectedBytes > 0 {
            let pct = Double(progress.downloadedBytes) / Double(progress.expectedBytes) * 100.0
            let mbNow = Double(progress.downloadedBytes) / 1024.0 / 1024.0
            let mbTotal = Double(progress.expectedBytes) / 1024.0 / 1024.0
            downloadProgressLabel.stringValue = String(format: "進捗: %.1f%% (%.1f / %.1f MB)", pct, mbNow, mbTotal)
        } else if progress.downloading {
            let mbNow = Double(progress.downloadedBytes) / 1024.0 / 1024.0
            downloadProgressLabel.stringValue = String(format: "進捗: %.1f MB", mbNow)
        } else {
            downloadProgressLabel.stringValue = "進捗: -"
        }
    }
}

final class LogsViewController: NSViewController, DashboardRefreshable {
    private let logTextView = NSTextView()
    private let copyButton = NSButton(title: "ログをコピー", target: nil, action: nil)

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.string = AppLog.shared.allText()

        let scroll = NSScrollView()
        scroll.documentView = logTextView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        copyButton.target = self
        copyButton.action = #selector(copyLog)

        view.addSubview(copyButton)
        view.addSubview(scroll)
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            copyButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refreshLogs), name: .logUpdated, object: nil)
    }

    @objc private func refreshLogs() {
        logTextView.string = AppLog.shared.allText()
        logTextView.scrollToEndOfDocument(nil)
    }

    @objc private func copyLog() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppLog.shared.allText(), forType: .string)
    }

    func refresh() {
        refreshLogs()
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
