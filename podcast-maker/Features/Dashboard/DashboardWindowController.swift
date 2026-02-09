import Cocoa
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController {
    private let viewModel: DashboardViewModel

    init(
        tracker: CostTracker,
        bedrock: BedrockService,
        onToggleRecording: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onGenerateDocuments: @escaping () -> Void
    ) {
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
        window.minSize = NSSize(width: 810, height: 525)
        window.contentViewController = hosting

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func refresh() {
        viewModel.refreshAll()
    }
}
