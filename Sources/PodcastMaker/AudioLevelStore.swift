import Foundation

final class AudioLevelStore {
    static let shared = AudioLevelStore()

    private let queue = DispatchQueue(label: "audio.level.store")
    private var levels: [Float] = []
    private let maxCount = 240

    private init() {}

    func append(level: Float) {
        queue.async {
            self.levels.append(level)
            if self.levels.count > self.maxCount {
                self.levels.removeFirst(self.levels.count - self.maxCount)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .audioLevelUpdated, object: nil)
            }
        }
    }

    func snapshot() -> [Float] {
        queue.sync { levels }
    }
}

extension AudioLevelStore: @unchecked Sendable {}
