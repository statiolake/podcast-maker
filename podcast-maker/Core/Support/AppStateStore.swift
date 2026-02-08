import Foundation

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
