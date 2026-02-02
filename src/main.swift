import Cocoa
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum AppState {
        case recording
        case paused
        case error(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")

    private let audioEngine = AVAudioEngine()
    private var isPaused = false
    private var state: AppState = .paused {
        didSet { updateUI() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        requestMicAccessAndStart()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
        } else {
            statusItem.button?.title = "PAUSE"
        }

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())

        pauseItem.target = self
        menu.addItem(pauseItem)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateUI()
    }

    private func requestMicAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startEngine()
                    } else {
                        self.state = .error("Mic permission denied")
                    }
                }
            }
        default:
            state = .error("Mic permission denied")
        }
    }

    private func startEngine() {
        let input = audioEngine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 1024

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if self.isPaused {
                return
            }
            // TODO: resample to 16k mono, feed ring buffer + VAD.
            _ = buffer.frameLength
        }

        do {
            try audioEngine.start()
            isPaused = false
            state = .recording
        } catch {
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
            pauseItem.title = "Pause"
            stateItem.title = "Recording"
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Recording")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "REC"
            }
        case .paused:
            pauseItem.title = "Resume"
            stateItem.title = "Paused"
            statusItem.button?.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Paused")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "PAUSE"
            }
        case .error(let message):
            pauseItem.title = "Resume"
            stateItem.title = "Error: \(message)"
            statusItem.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            if statusItem.button?.image == nil {
                statusItem.button?.title = "ERR"
            }
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        if isPaused {
            state = .paused
        } else {
            state = .recording
        }
    }

    @objc private func openSettings() {
        let alert = NSAlert()
        alert.messageText = "Settings"
        alert.informativeText = "Not implemented yet."
        alert.runModal()
    }

    @objc private func quit() {
        stopEngineIfRunning()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
