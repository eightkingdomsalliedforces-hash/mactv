import AppKit
import SwiftUI

@MainActor
public struct ShellWindowConfigurator: NSViewRepresentable {
    private static var didRequestInitialFullScreen = false
    private static weak var configuredWindow: NSWindow?

    public init() {}

    public static func toggleFocusedWindowFullScreen() {
        guard let window = preferredWindow() else {
            return
        }
        configureForTVMode(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.toggleFullScreen(nil)
    }

    public static func enterKnownWindowFullScreen() {
        guard let window = preferredWindow() else {
            return
        }
        configureForTVMode(window)
        enterFullScreen(window)
    }

    private static func preferredWindow() -> NSWindow? {
        configuredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
    }

    private static func configureForTVMode(_ window: NSWindow) {
        configuredWindow = window
        window.title = "MacTV"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.collectionBehavior.formUnion([.fullScreenPrimary, .managed])
        window.minSize = NSSize(width: 960, height: 540)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }

    private static func enterFullScreen(_ window: NSWindow) {
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

        Self.configureForTVMode(window)
        requestInitialFullScreen(window)
    }

    private func requestInitialFullScreen(_ window: NSWindow) {
        guard Self.didRequestInitialFullScreen == false,
              window.styleMask.contains(.fullScreen) == false
        else {
            return
        }
        Self.didRequestInitialFullScreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Self.enterFullScreen(window)
        }
    }
}

@MainActor
public final class ShellAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ShellWindowConfigurator.enterKnownWindowFullScreen()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async {
            ShellWindowConfigurator.enterKnownWindowFullScreen()
        }
        return true
    }
}
