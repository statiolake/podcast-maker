import Cocoa

final class RecentDocumentsMenu {
    private let store = DocumentStore()
    private var playerWindow: PlayerWindowController?

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let items = store.recentDocuments(limit: 10)
        if items.isEmpty {
            menu.addItem(NSMenuItem(title: "（なし）", action: nil, keyEquivalent: ""))
            return menu
        }

        for folder in items {
            let title = formatTitle(folder: folder)
            let item = NSMenuItem(title: title, action: #selector(openDocument(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folder
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openDocument(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? URL else { return }
        let audioURL = folder.appendingPathComponent("audio.wav")
        guard let metadata = store.loadMetadata(at: folder) else { return }
        playerWindow = PlayerWindowController(audioURL: audioURL, metadata: metadata)
        playerWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func formatTitle(folder: URL) -> String {
        if let metadata = store.loadMetadata(at: folder) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
            let start = Date(timeIntervalSince1970: metadata.startTime)
            let end = Date(timeIntervalSince1970: metadata.endTime)
            let startStr = formatter.string(from: start)
            let endStr = formatter.string(from: end)
            return "\(metadata.title) (\(startStr) 〜 \(endStr.split(separator: " ").last ?? Substring("")))"
        }
        return folder.lastPathComponent
    }
}
