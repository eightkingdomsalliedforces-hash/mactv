import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var activeRuntime: ActiveRuntime = .launcher
    @Published public var focusedAppID: UUID?
    @Published public var lastCommand: RemoteCommand?
    @Published public var apps: [TVAppProfile]
    @Published public var displayScale: DisplayScale = .auto
    @Published public var statusMessage: String?

    private let nativeRuntime = NativeAppRuntime()

    public init(apps: [TVAppProfile] = SeedApps.defaultApps) {
        self.apps = apps
        focusedAppID = apps.first?.id
    }

    public func handle(_ command: RemoteCommand) {
        lastCommand = command

        switch activeRuntime {
        case .launcher:
            handleLauncher(command)
        case .settings:
            handleSettings(command)
        case .web, .media, .native, .remoteLearning:
            handleRuntimeCommand(command)
        }
    }

    private func handleLauncher(_ command: RemoteCommand) {
        switch command {
        case .left:
            moveFocusedApp(command)
        case .right:
            moveFocusedApp(command)
        case .up, .down:
            moveFocusedApp(command)
        case .select:
            openFocusedApp()
        case .home:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home || command == .back {
            activeRuntime = .launcher
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if activeRuntime == .remoteLearning, command == .select {
            AccessibilityScanner.requestTrustPrompt()
            return
        }

        NotificationCenter.default.post(
            name: .tvShellRuntimeCommand,
            object: nil,
            userInfo: [RuntimeCommandNotification.commandKey: command]
        )
    }

    private func handleSettings(_ command: RemoteCommand) {
        switch command {
        case .left:
            displayScale = displayScale.previous
        case .right, .select:
            displayScale = displayScale.next
        case .home, .back:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func moveFocusedApp(_ command: RemoteCommand) {
        focusedAppID = LauncherLayout.focusedApp(
            after: command,
            currentID: focusedAppID,
            sections: LauncherLayout.sections(for: apps)
        )
    }

    private func openFocusedApp() {
        guard let app = apps.first(where: { $0.id == focusedAppID }) else {
            return
        }

        switch app.target {
        case let .web(url) where url.scheme == "tv-shell" && url.host == "remote-learning":
            statusMessage = "Opening Remote Setup"
            activeRuntime = .remoteLearning
        case let .web(url) where url.scheme == "tv-shell" && url.host == "settings":
            statusMessage = "Opening Settings"
            activeRuntime = .settings
        case .web:
            statusMessage = "Opening \(app.name)"
            activeRuntime = .web(app)
        case .media:
            statusMessage = "Opening \(app.name)"
            activeRuntime = .media(app)
        case .nativeApp:
            statusMessage = "Opening \(app.name)"
            activeRuntime = .native(app)
            nativeRuntime.launch(app) { [weak self] success, message in
                Task { @MainActor in
                    self?.statusMessage = success ? message : "Failed: \(message)"
                }
            }
        }
    }
}
