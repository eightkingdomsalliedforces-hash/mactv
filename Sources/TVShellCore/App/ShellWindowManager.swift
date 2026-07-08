import AppKit
import SwiftUI

public struct ShellWindowConfigurator: NSViewRepresentable {
    private static var didRequestInitialFullScreen = false

    public init() {}

    public static func toggleFocusedWindowFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return
        }
        enterFullScreen(window)
    }

    public static func enterFullScreen(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard window.styleMask.contains(.fullScreen) == false else {
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
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.formUnion([.fullScreenPrimary, .managed])
        window.minSize = NSSize(width: 960, height: 540)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.isMovableByWindowBackground = true
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isHidden = false
            zoomButton.isEnabled = true
            zoomButton.target = FullScreenButtonTarget.shared
            zoomButton.action = #selector(FullScreenButtonTarget.toggleFullScreen(_:))
        }
        requestInitialFullScreen(window)
    }

    private func requestInitialFullScreen(_ window: NSWindow) {
        guard Self.didRequestInitialFullScreen == false,
              window.styleMask.contains(.fullScreen) == false
        else {
            return
        }
        Self.didRequestInitialFullScreen = true
        for delay in [0.15, 0.65, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.enterFullScreen(window)
            }
        }
    }
}

@MainActor
private final class FullScreenButtonTarget: NSObject {
    static let shared = FullScreenButtonTarget()

    @objc func toggleFullScreen(_ sender: Any?) {
        ShellWindowConfigurator.toggleFocusedWindowFullScreen()
    }
}
