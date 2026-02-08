import Cocoa
import AVFoundation

private func makeAudioTapHandler(pipeline: AudioPipeline) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    return { buffer, _ in
        if AppStateStore.shared.isPaused {
            return
        }
        pipeline.handle(buffer: buffer)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum AppState {
        case recording
        case paused
        case error(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")

    private let audioEngine = AVAudioEngine()
    private let pipeline = AudioPipeline()
    private let importer = AudioImporter()
    private let costTracker = CostTracker()
    private lazy var bedrockService = BedrockService(tracker: costTracker)
    private var dashboardWindow: DashboardWindowController?
    private var isPaused = false
    private var state: AppState = .paused {
        didSet { updateUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        AppLog.shared.add("App launched")
        ModelManager.shared.ensureModelAvailable()
        requestMicAccessAndStart()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            statusItem.button?.title = "PAUSE"
        }

        pauseItem.target = self
        menu.addItem(pauseItem)

        let dashboardItem = NSMenuItem(title: "ダッシュボード", action: #selector(openDashboard), keyEquivalent: ",")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        updateUI()
    }

    @objc private func handleStatusBarClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            openDashboard()
            return
        }
        if event.type == .rightMouseUp {
            guard let button = statusItem.button else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            openDashboard()
        }
    }

    private func requestMicAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            AppLog.shared.add("Mic permission already authorized")
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        AppLog.shared.add("Mic permission granted")
                        self.startEngine()
                    } else {
                        AppLog.shared.add("Mic permission denied")
                        self.state = .error("Mic permission denied")
                    }
                }
            }
        default:
            AppLog.shared.add("Mic permission denied")
            state = .error("Mic permission denied")
        }
    }

    private func startEngine() {
        let input = audioEngine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 1024
        let tapHandler = makeAudioTapHandler(pipeline: pipeline)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat, block: tapHandler)

        do {
            try audioEngine.start()
            isPaused = false
            state = .recording
            AppLog.shared.add("Audio engine started")
        } catch {
            AppLog.shared.add("Audio engine start failed: \(error.localizedDescription)")
            state = .error("Audio start failed")
        }
    }

    private func stopEngineIfRunning() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func updateUI() {
        switch state {
        case .recording:
            pauseItem.title = "録音停止"
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "REC"
            }
            AppStateStore.shared.setPaused(false)
        case .paused:
            pauseItem.title = "録音開始"
            statusItem.button?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "PAUSE"
            }
            AppStateStore.shared.setPaused(true)
        case .error:
            pauseItem.title = "録音開始"
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "ERR"
            }
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            AppLog.shared.add("Paused")
            state = .paused
        } else {
            AppLog.shared.add("Resumed")
            state = .recording
        }
    }

    @objc private func openDashboard() {
        if dashboardWindow == nil {
            dashboardWindow = DashboardWindowController(
                tracker: costTracker,
                bedrock: bedrockService,
                onToggleRecording: { [weak self] in self?.togglePause() },
                onImport: { [weak self] in self?.importAudio() },
                onGenerateDocuments: { [weak self] in self?.generateDocuments() }
            )
        }
        dashboardWindow?.refresh()
        dashboardWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func generateDocuments() {
        let builder = DocumentBuilder(bedrock: bedrockService)
        AppLog.shared.add("Document build requested (3h)")
        builder.buildDocuments(hours: 3, profile: costTracker.awsProfile) { [weak self] success in
            Task { @MainActor [weak self] in
                AppLog.shared.add(success ? "Document build completed" : "Document build failed")
                self?.dashboardWindow?.refresh()
            }
        }
    }

    @objc private func importAudio() {
        let panel = NSOpenPanel()
        panel.title = "音声ファイルをインポート"
        panel.message = "WAV または M4A ファイルを選択してください"
        panel.allowedContentTypes = [.wav, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            importer.importFile(url: url, pipeline: pipeline)
        }
    }

    @objc private func quit() {
        stopEngineIfRunning()
        NSApplication.shared.terminate(nil)
    }
}
