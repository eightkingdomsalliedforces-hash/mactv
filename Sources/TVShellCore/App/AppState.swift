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
    @Published public var focusedManagementAppID: UUID?
    @Published public var wallpaperSource: WallpaperSource = .builtIn(.aurora)
    @Published public var settingsFocus: SettingsFocus = .scale
    @Published public var webRemoteMode: WebRemoteMode = .keyboard

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
        case .appManagement:
            handleAppManagement(command)
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

        if case .web = activeRuntime, command == .menu {
            webRemoteMode = webRemoteMode.next
            statusMessage = "Web Mode: \(webRemoteMode.title)"
            NotificationCenter.default.post(
                name: .tvShellRuntimeCommand,
                object: nil,
                userInfo: [
                    RuntimeCommandNotification.commandKey: command,
                    RuntimeCommandNotification.webModeKey: webRemoteMode
                ]
            )
            return
        }

        if activeRuntime == .remoteLearning, command == .select {
            AccessibilityScanner.requestTrustPrompt()
            return
        }

        NotificationCenter.default.post(
            name: .tvShellRuntimeCommand,
            object: nil,
            userInfo: [
                RuntimeCommandNotification.commandKey: command,
                RuntimeCommandNotification.webModeKey: webRemoteMode
            ]
        )
    }

    private func handleSettings(_ command: RemoteCommand) {
        switch command {
        case .up:
            settingsFocus = settingsFocus.previous
        case .down:
            settingsFocus = settingsFocus.next
        case .left:
            changeFocusedSetting(previous: true)
        case .right, .select:
            changeFocusedSetting(previous: false)
        case .home, .back:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func changeFocusedSetting(previous: Bool) {
        switch settingsFocus {
        case .scale:
            displayScale = previous ? displayScale.previous : displayScale.next
        case .wallpaper:
            let currentPreset = wallpaperSource.preset ?? .aurora
            wallpaperSource = .builtIn(previous ? currentPreset.previous : currentPreset.next)
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
            setRuntime(.remoteLearning)
        case let .web(url) where url.scheme == "tv-shell" && url.host == "settings":
            statusMessage = "Opening Settings"
            setRuntime(.settings)
        case let .web(url) where url.scheme == "tv-shell" && url.host == "app-management":
            statusMessage = "Opening App Management"
            focusedManagementAppID = apps.first?.id
            setRuntime(.appManagement)
        case .web:
            statusMessage = "Opening \(app.name)"
            setRuntime(.web(app))
        case .media:
            statusMessage = "Opening \(app.name)"
            setRuntime(.media(app))
        case .nativeApp:
            statusMessage = "Opening \(app.name)"
            setRuntime(.native(app))
            nativeRuntime.launch(app) { [weak self] success, message in
                Task { @MainActor in
                    self?.statusMessage = success ? message : "Failed: \(message)"
                }
            }
        }
    }

    private func setRuntime(_ runtime: ActiveRuntime) {
        withAnimation(TVMotion.runtime) {
            activeRuntime = runtime
        }
    }

    private func handleAppManagement(_ command: RemoteCommand) {
        switch command {
        case .left:
            moveManagedApp(.left)
        case .right:
            moveManagedApp(.right)
        case .up:
            moveManagedFocus(by: -1)
        case .down:
            moveManagedFocus(by: 1)
        case .select:
            if let focusedManagementAppID {
                var catalog = AppCatalog(apps: apps)
                catalog.toggleVisibility(for: focusedManagementAppID)
                apps = catalog.apps
            }
        case .home, .back:
            activeRuntime = .launcher
            focusedAppID = LauncherLayout.sections(for: apps).flatMap(\.apps).first?.id
        default:
            break
        }
    }

    private func moveManagedFocus(by offset: Int) {
        guard let focusedManagementAppID,
              let index = apps.firstIndex(where: { $0.id == focusedManagementAppID })
        else {
            self.focusedManagementAppID = apps.first?.id
            return
        }

        let nextIndex = min(max(index + offset, 0), apps.count - 1)
        self.focusedManagementAppID = apps[nextIndex].id
    }

    private func moveManagedApp(_ direction: CatalogMoveDirection) {
        guard let focusedManagementAppID else {
            return
        }
        var catalog = AppCatalog(apps: apps)
        catalog.moveApp(id: focusedManagementAppID, direction: direction)
        apps = catalog.apps
    }
}
