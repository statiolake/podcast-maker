import Cocoa

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let tracker: CostTracker
    private let bedrock: BedrockService
    private let awsField = NSTextField(string: "")
    private let inputTokensLabel = NSTextField(labelWithString: "")
    private let outputTokensLabel = NSTextField(labelWithString: "")
    private let cacheTokensLabel = NSTextField(labelWithString: "")
    private let totalCostLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Bedrock ステータス: 待機中")
    private let testButton = NSButton(title: "Bedrock テスト", target: nil, action: nil)
    private let copyLogButton = NSButton(title: "ログをコピー", target: nil, action: nil)
    private let tabView = NSTabView()
    private let logTextView = NSTextView()
    private let queueStatusLabel = NSTextField(labelWithString: "")
    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let downloadStatusLabel = NSTextField(labelWithString: "")
    private let downloadProgressLabel = NSTextField(labelWithString: "")

    init(tracker: CostTracker, bedrock: BedrockService) {
        self.tracker = tracker
        self.bedrock = bedrock
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "設定"
        super.init(window: window)
        setupUI()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLogs), name: .logUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshQueue), name: .queueUpdated, object: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "Bedrock（Claude Haiku 4.5）")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        let modelLabel = NSTextField(labelWithString: "モデル: \(HaikuPricing.modelId)")
        modelLabel.font = NSFont.systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        testButton.target = self
        testButton.action = #selector(runBedrockTest)

        copyLogButton.target = self
        copyLogButton.action = #selector(copyLogToClipboard)

        let awsLabel = NSTextField(labelWithString: "AWS_PROFILE")
        awsField.placeholderString = "default"
        awsField.delegate = self

        let tokensTitle = NSTextField(labelWithString: "トークン使用量")
        tokensTitle.font = NSFont.boldSystemFont(ofSize: 12)

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
            testButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let settingsView = NSView()
        settingsView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: settingsView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: settingsView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: settingsView.topAnchor, constant: 20)
        ])

        logTextView.isEditable = false
        logTextView.isSelectable = true
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.string = AppLog.shared.allText()

        let scrollView = NSScrollView()
        scrollView.documentView = logTextView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let logView = NSView()
        logView.addSubview(copyLogButton)
        logView.addSubview(scrollView)
        copyLogButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            copyLogButton.trailingAnchor.constraint(equalTo: logView.trailingAnchor, constant: -12),
            copyLogButton.topAnchor.constraint(equalTo: logView.topAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: logView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: logView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: copyLogButton.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: logView.bottomAnchor, constant: -12)
        ])

        tabView.translatesAutoresizingMaskIntoConstraints = false
        let settingsTab = NSTabViewItem(identifier: "settings")
        settingsTab.label = "設定"
        settingsTab.view = settingsView
        let logTab = NSTabViewItem(identifier: "log")
        logTab.label = "ログ"
        logTab.view = logView
        let queueTab = NSTabViewItem(identifier: "queue")
        queueTab.label = "キュー"

        let queueView = NSView()
        let queueStack = NSStackView(views: [modelStatusLabel, downloadStatusLabel, downloadProgressLabel, queueStatusLabel])
        queueStack.orientation = .vertical
        queueStack.alignment = .leading
        queueStack.spacing = 8
        queueStack.translatesAutoresizingMaskIntoConstraints = false
        queueView.addSubview(queueStack)
        NSLayoutConstraint.activate([
            queueStack.leadingAnchor.constraint(equalTo: queueView.leadingAnchor, constant: 20),
            queueStack.trailingAnchor.constraint(equalTo: queueView.trailingAnchor, constant: -20),
            queueStack.topAnchor.constraint(equalTo: queueView.topAnchor, constant: 20)
        ])
        queueTab.view = queueView

        tabView.addTabViewItem(settingsTab)
        tabView.addTabViewItem(logTab)
        tabView.addTabViewItem(queueTab)

        content.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: content.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
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

    @objc private func refreshLogs() {
        logTextView.string = AppLog.shared.allText()
        logTextView.scrollToEndOfDocument(nil)
    }

    @objc private func copyLogToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppLog.shared.allText(), forType: .string)
    }

    @objc private func refreshQueue() {
        let status = WhisperASRWorker.shared.queueStatus()
        let progress = ModelManager.shared.status()
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
