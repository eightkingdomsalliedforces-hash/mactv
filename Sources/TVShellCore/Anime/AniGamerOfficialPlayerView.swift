import AppKit
import SwiftUI
import WebKit

public struct AniGamerOfficialPlayerView: NSViewRepresentable {
    public let url: URL
    public let onExit: @MainActor () -> Void

    public init(url: URL, onExit: @escaping @MainActor () -> Void) {
        self.url = url
        self.onExit = onExit
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onExit: onExit)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        context.coordinator.attach(to: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onExit = onExit
        guard webView.url?.absoluteString != url.absoluteString else { return }
        webView.load(URLRequest(url: url))
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var onExit: @MainActor () -> Void
        private nonisolated(unsafe) var observer: NSObjectProtocol?
        private var lastBackDate = Date.distantPast

        init(onExit: @escaping @MainActor () -> Void) {
            self.onExit = onExit
            super.init()
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            observer = NotificationCenter.default.addObserver(
                forName: .tvShellRuntimeCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else { return }
                Task { @MainActor [weak self] in
                    self?.handle(command)
                }
            }
        }

        private func handle(_ command: RemoteCommand) {
            switch command {
            case .up:
                sendKey(code: 126, characters: functionKey(NSUpArrowFunctionKey))
            case .down:
                sendKey(code: 125, characters: functionKey(NSDownArrowFunctionKey))
            case .left, .rewind:
                sendKey(code: 123, characters: functionKey(NSLeftArrowFunctionKey))
            case .right, .fastForward:
                sendKey(code: 124, characters: functionKey(NSRightArrowFunctionKey))
            case .select:
                sendKey(code: 49, characters: " ")
            case .playPause:
                sendKey(code: 40, characters: "k")
            case .back, .menu:
                sendKey(code: 53, characters: "\u{1b}")
                let now = Date()
                if now.timeIntervalSince(lastBackDate) < 1.1 {
                    onExit()
                }
                lastBackDate = now
            case .home:
                onExit()
            default:
                break
            }
        }

        private func sendKey(code: UInt16, characters: String) {
            guard let webView else { return }
            let windowNumber = webView.window?.windowNumber ?? 0
            let timestamp = ProcessInfo.processInfo.systemUptime
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(
                    with: type,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: timestamp,
                    windowNumber: windowNumber,
                    context: nil,
                    characters: characters,
                    charactersIgnoringModifiers: characters,
                    isARepeat: false,
                    keyCode: code
                ) else { continue }
                if type == .keyDown {
                    webView.keyDown(with: event)
                } else {
                    webView.keyUp(with: event)
                }
            }
        }

        private func functionKey(_ value: Int) -> String {
            UnicodeScalar(value).map(String.init) ?? ""
        }
    }
}
