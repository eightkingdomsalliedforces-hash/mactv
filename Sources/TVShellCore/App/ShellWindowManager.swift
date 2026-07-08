import AppKit
import SwiftUI

@MainActor
public struct ShellWindowConfigurator: NSViewRepresentable {
    private static var didRequestInitialFullScreen = false
    private static weak var configuredWindow: NSWindow?
    private static var fullScreenFallbackTask: DispatchWorkItem?
    private static var fallbackWindowID: ObjectIdentifier?
    private static var fallbackSnapshot: WindowedSnapshot?

    public init() {}

    public static func toggleFocusedWindowFullScreen() {
        guard let window = preferredWindow() else {
            return
        }

        if isBorderlessTVFullScreen(window) {
            restoreWindowedMode(window)
            return
        }

        configureForTVMode(window)
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            enterFullScreen(window)
        }
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
        guard isBorderlessTVFullScreen(window) == false else {
            return
        }
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
        _ = NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard window.styleMask.contains(.fullScreen) == false else {
            return
        }
        window.toggleFullScreen(nil)
        scheduleBorderlessFallback(for: window)
    }

    private static func scheduleBorderlessFallback(for window: NSWindow) {
        fullScreenFallbackTask?.cancel()
        let task = DispatchWorkItem { [weak window] in
            Task { @MainActor in
                guard let window,
                      window.styleMask.contains(.fullScreen) == false,
                      isBorderlessTVFullScreen(window) == false
                else {
                    return
                }
                enterBorderlessTVFullScreen(window)
            }
        }
        fullScreenFallbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: task)
    }

    private static func enterBorderlessTVFullScreen(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        let screenFrame: NSRect
        if let screen {
            screenFrame = screen.frame
        } else {
            screenFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        }

        fallbackWindowID = ObjectIdentifier(window)
        fallbackSnapshot = WindowedSnapshot(
            frame: window.frame,
            styleMask: window.styleMask,
            level: window.level,
            collectionBehavior: window.collectionBehavior,
            titleVisibility: window.titleVisibility,
            titlebarAppearsTransparent: window.titlebarAppearsTransparent
        )

        window.styleMask = [.borderless]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .stationary, .fullScreenAuxiliary])
        window.level = .normal
        window.setFrame(screenFrame, display: true, animate: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
    }

    private static func restoreWindowedMode(_ window: NSWindow) {
        guard let snapshot = fallbackSnapshot else {
            return
        }
        NSApp.presentationOptions = NSApplication.PresentationOptions()
        fallbackWindowID = nil
        fallbackSnapshot = nil
        window.styleMask = snapshot.styleMask
        window.titleVisibility = snapshot.titleVisibility
        window.titlebarAppearsTransparent = snapshot.titlebarAppearsTransparent
        window.collectionBehavior = snapshot.collectionBehavior
        window.level = snapshot.level
        window.setFrame(snapshot.frame, display: true, animate: true)
        configureForTVMode(window)
    }

    private static func isBorderlessTVFullScreen(_ window: NSWindow) -> Bool {
        fallbackWindowID == ObjectIdentifier(window)
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
        _ = NSApp.setActivationPolicy(.regular)
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

private struct WindowedSnapshot {
    var frame: NSRect
    var styleMask: NSWindow.StyleMask
    var level: NSWindow.Level
    var collectionBehavior: NSWindow.CollectionBehavior
    var titleVisibility: NSWindow.TitleVisibility
    var titlebarAppearsTransparent: Bool
}
