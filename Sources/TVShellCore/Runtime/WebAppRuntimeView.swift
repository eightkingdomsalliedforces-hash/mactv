import SwiftUI
import WebKit

public struct WebAppRuntimeView: NSViewRepresentable {
    public let app: TVAppProfile

    public init(app: TVAppProfile) {
        self.app = app
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userScript = WKUserScript(
            source: Self.remoteBridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(to: webView)

        if case let .web(url) = app.target {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    public final class Coordinator {
        private weak var webView: WKWebView?
        private nonisolated(unsafe) var observer: NSObjectProtocol?

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: .tvShellRuntimeCommand,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else {
                        return
                    }
                    let mode = notification.userInfo?[RuntimeCommandNotification.webModeKey] as? WebRemoteMode ?? .keyboard
                    Task { @MainActor [weak self] in
                        self?.send(command, mode: mode)
                    }
                }
            }
        }

        private func send(_ command: RemoteCommand, mode: WebRemoteMode) {
            guard let webView else {
                return
            }

            let jsCommand = command.javascriptName
            guard jsCommand.isEmpty == false else {
                return
            }

            webView.evaluateJavaScript("window.tvShellCommand && window.tvShellCommand('\(jsCommand)', '\(mode.rawValue)')") { _, _ in }
        }
    }

    public static let remoteBridgeScript = """
    (() => {
      if (window.__tvShellInstalled) return;
      window.__tvShellInstalled = true;

      const style = document.createElement('style');
      style.textContent = `
        :focus {
          outline: 6px solid rgba(255,255,255,.96) !important;
          outline-offset: 8px !important;
        }
        button, a, input, select, textarea, [role="button"], [tabindex] {
          min-height: 44px !important;
          min-width: 44px !important;
        }
      `;
      document.documentElement.appendChild(style);

      window.tvShellCommand = (command, mode = 'keyboard') => {
        const keyForCommand = {
          up: 'ArrowUp',
          down: 'ArrowDown',
          left: 'ArrowLeft',
          right: 'ArrowRight',
          select: 'Enter',
          back: 'Escape',
          playPause: ' '
        }[command];

        const dispatchKey = () => {
          if (!keyForCommand) return false;
          const eventInit = {
            key: keyForCommand,
            code: keyForCommand === ' ' ? 'Space' : keyForCommand,
            bubbles: true,
            cancelable: true,
            composed: true
          };
          document.dispatchEvent(new KeyboardEvent('keydown', eventInit));
          if (document.activeElement) {
            document.activeElement.dispatchEvent(new KeyboardEvent('keydown', eventInit));
          }
          document.dispatchEvent(new KeyboardEvent('keyup', eventInit));
          return true;
        };

        const active = document.activeElement;
        const focusables = Array.from(document.querySelectorAll('a, button, input, select, textarea, video, [role="button"], [tabindex]:not([tabindex="-1"])'))
          .filter(el => !el.disabled && el.offsetParent !== null);

        const currentIndex = Math.max(0, focusables.indexOf(active));
        const focusAt = (index) => {
          const next = focusables[Math.max(0, Math.min(index, focusables.length - 1))];
          if (next && next.focus) {
            next.focus({ preventScroll: false });
            next.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
          } else if (command === 'down') {
            window.scrollBy({ top: window.innerHeight * 0.65, behavior: 'smooth' });
          } else if (command === 'up') {
            window.scrollBy({ top: -window.innerHeight * 0.65, behavior: 'smooth' });
          }
        };

        const scrollByCommand = () => {
          if (command === 'down') window.scrollBy({ top: window.innerHeight * 0.65, behavior: 'smooth' });
          if (command === 'up') window.scrollBy({ top: -window.innerHeight * 0.65, behavior: 'smooth' });
          if (command === 'right') window.scrollBy({ left: window.innerWidth * 0.65, behavior: 'smooth' });
          if (command === 'left') window.scrollBy({ left: -window.innerWidth * 0.65, behavior: 'smooth' });
          return ['up', 'down', 'left', 'right'].includes(command);
        };

        if (mode === 'keyboard') {
          const sent = dispatchKey();
          if (command === 'select' && active && active.click) active.click();
          if (command === 'playPause') {
            const video = document.querySelector('video');
            if (video) {
              if (video.paused) video.play(); else video.pause();
            }
          }
          return sent;
        }

        if (mode === 'scroll') {
          if (command === 'select' && active && active.click) return active.click(), true;
          if (command === 'playPause') dispatchKey();
          return scrollByCommand();
        }

        if (command === 'select') {
          if (active && active.click) active.click();
          dispatchKey();
          return true;
        }
        if (command === 'back') {
          dispatchKey();
          history.back();
          return true;
        }
        if (command === 'down' || command === 'right') {
          dispatchKey();
          focusAt(currentIndex + 1);
          return true;
        }
        if (command === 'up' || command === 'left') {
          dispatchKey();
          focusAt(currentIndex - 1);
          return true;
        }
        if (command === 'playPause') {
          const video = document.querySelector('video');
          if (video) {
            if (video.paused) video.play(); else video.pause();
            return true;
          }
          dispatchKey();
        }
        return false;
      };
    })();
    """
}

private extension RemoteCommand {
    var javascriptName: String {
        switch self {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .select: "select"
        case .back: "back"
        case .playPause: "playPause"
        default: ""
        }
    }
}
