import Cocoa

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    private let tracker: CostTracker
    private let bedrock: BedrockService
    private let awsField = NSTextField(string: "")
    private let inputTokensLabel = NSTextField(labelWithString: "")
    private let outputTokensLabel = NSTextField(labelWithString: "")
    private let cacheTokensLabel = NSTextField(labelWithString: "")
    private let totalCostLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "Bedrock status: idle")
    private let testButton = NSButton(title: "Test Bedrock", target: nil, action: nil)
    private let tabView = NSTabView()
    private let logTextView = NSTextView()

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
        window.title = "Settings"
        super.init(window: window)
        setupUI()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLogs), name: .logUpdated, object: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "Bedrock (Claude Haiku 4.5)")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        let modelLabel = NSTextField(labelWithString: "Model: \(HaikuPricing.modelId)")
        modelLabel.font = NSFont.systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        testButton.target = self
        testButton.action = #selector(runBedrockTest)

        let awsLabel = NSTextField(labelWithString: "AWS_PROFILE")
        awsField.placeholderString = "default"
        awsField.delegate = self

        let tokensTitle = NSTextField(labelWithString: "Token Usage")
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
        logView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: logView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: logView.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: logView.topAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: logView.bottomAnchor, constant: -12)
        ])

        tabView.translatesAutoresizingMaskIntoConstraints = false
        let settingsTab = NSTabViewItem(identifier: "settings")
        settingsTab.label = "Settings"
        settingsTab.view = settingsView
        let logTab = NSTabViewItem(identifier: "log")
        logTab.label = "Log"
        logTab.view = logView
        tabView.addTabViewItem(settingsTab)
        tabView.addTabViewItem(logTab)

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
        inputTokensLabel.stringValue = "Input tokens: \(tracker.inputTokens)"
        outputTokensLabel.stringValue = "Output tokens: \(tracker.outputTokens)"
        cacheTokensLabel.stringValue = "Cache tokens (5m/1h/hit): \(tracker.cacheWrite5mTokens) / \(tracker.cacheWrite1hTokens) / \(tracker.cacheHitTokens)"
        totalCostLabel.stringValue = String(format: "Estimated total cost: $%.4f", tracker.totalCostUSD())
    }

    @objc private func runBedrockTest() {
        testButton.isEnabled = false
        statusLabel.stringValue = "Bedrock status: running..."

        let profile = tracker.awsProfile
        let prompt = "Return a single short sentence saying hello."

        Task {
            do {
                _ = try await bedrock.test(prompt: prompt, profile: profile)
                DispatchQueue.main.async { [weak self] in
                    self?.refresh()
                    self?.statusLabel.stringValue = "Bedrock status: success"
                    self?.testButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    AppLog.shared.add("Bedrock test failed: \(error.localizedDescription)")
                    self?.statusLabel.stringValue = "Bedrock status: error"
                    self?.testButton.isEnabled = true
                }
            }
        }
    }

    @objc private func refreshLogs() {
        logTextView.string = AppLog.shared.allText()
        logTextView.scrollToEndOfDocument(nil)
    }
}
