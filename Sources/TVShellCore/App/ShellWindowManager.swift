import AppKit
import SwiftUI

public struct ShellWindowConfigurator: NSViewRepresentable {
    private static var didRequestInitialFullScreen = false

    public init() {}

    public static func toggleFocusedWindowFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }
        window.toggleFullScreen(nil)
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        window.title = "MacTV"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
        window.styleMask.remove(.fullSizeContentView)
        window.collectionBehavior.formUnion([.fullScreenPrimary, .managed])
        window.minSize = NSSize(width: 960, height: 540)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = true
        requestInitialFullScreen(window)
    }

    private func requestInitialFullScreen(_ window: NSWindow) {
        guard Self.didRequestInitialFullScreen == false,
              window.styleMask.contains(.fullScreen) == false
        else {
            return
        }
        Self.didRequestInitialFullScreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            window.toggleFullScreen(nil)
        }
    }
}
