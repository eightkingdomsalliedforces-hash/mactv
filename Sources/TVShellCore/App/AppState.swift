import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    @Published public var webZoom: Double = 1.25
    @Published public var videoSourceLabel: String = "內建示範影片"
    @Published public var dandanplayCredentials: DandanplayCredentials = .environment()
    @Published public var youtubeCredentials: YouTubeCredentials = .environment()
    @Published public var openingAppName: String?
    @Published public var animeSourceCatalog: AnimeSourceCatalogState
    @Published public var focusedAnimeSourceID: String?

    private let nativeRuntime = NativeAppRuntime()
    private nonisolated(unsafe) var exitObserver: NSObjectProtocol?

    public init(apps: [TVAppProfile] = SeedApps.defaultApps) {
        self.apps = apps
        animeSourceCatalog = AnimeSourceCatalogState(definitions: AnimeSourceCatalog.defaultSources)
        focusedAppID = apps.first?.id
        focusedAnimeSourceID = animeSourceCatalog.focusedID
        exitObserver = NotificationCenter.default.addObserver(
            forName: .tvShellRequestLauncher,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.activeRuntime = .launcher
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    deinit {
        if let exitObserver {
            NotificationCenter.default.removeObserver(exitObserver)
        }
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
        case .animeSourceManagement:
            handleAnimeSourceManagement(command)
        case .web, .media, .anime, .youtube, .native, .remoteLearning:
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
        if command == .home || (command == .back && activeRuntime.handlesBackInternally == false) {
            activeRuntime = .launcher
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if case .web = activeRuntime, command == .menu {
            webRemoteMode = webRemoteMode.next
            statusMessage = "網頁模式：\(webRemoteMode.title)"
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
        case .webZoom:
            let delta = previous ? -0.1 : 0.1
            webZoom = min(max((webZoom + delta) * 10, 8), 24) / 10
        case .videoSource:
            chooseVideoFile()
        }
    }

    private func chooseVideoFile() {
        let panel = NSOpenPanel()
        panel.title = "選擇影片"
        panel.prompt = "選擇"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "mkv") ?? .movie,
            UTType(filenameExtension: "avi") ?? .movie
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            statusMessage = "未選擇影片"
            return
        }

        updateVideoApp(url: url, label: url.lastPathComponent)
    }

    private func updateVideoApp(url: URL, label: String) {
        guard let index = apps.firstIndex(where: { $0.name == "Video" || $0.name == "影片" }) else {
            statusMessage = "找不到影片 App"
            return
        }

        apps[index].name = "影片"
        apps[index].target = .media(url)
        videoSourceLabel = label
        statusMessage = "影片來源：\(label)"
        focusedAppID = apps[index].id
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

        showOpeningAnimation(for: app.name)

        switch app.target {
        case let .web(url) where url.scheme == "tv-shell" && url.host == "remote-learning":
            statusMessage = "正在開啟遙控器設定"
            setRuntime(.remoteLearning)
        case let .web(url) where url.scheme == "tv-shell" && url.host == "settings":
            statusMessage = "正在開啟設定"
            setRuntime(.settings)
        case let .web(url) where url.scheme == "tv-shell" && url.host == "app-management":
            statusMessage = "正在開啟 App 管理"
            focusedManagementAppID = apps.first?.id
            setRuntime(.appManagement)
        case let .web(url) where url.scheme == "tv-shell" && url.host == "anime-sources":
            statusMessage = "正在開啟動漫來源"
            focusedAnimeSourceID = animeSourceCatalog.focusedID ?? animeSourceCatalog.instances.first?.id
            setRuntime(.animeSourceManagement)
        case .web:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.web(app))
        case .media:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.media(app))
        case .anime:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.anime(app))
        case .youtube:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.youtube(app))
        case .nativeApp:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.native(app))
            nativeRuntime.launch(app) { [weak self] success, message in
                Task { @MainActor in
                    self?.statusMessage = success ? message : "失敗：\(message)"
                }
            }
        }
    }

    private func setRuntime(_ runtime: ActiveRuntime) {
        withAnimation(TVMotion.runtime) {
            activeRuntime = runtime
        }
    }

    private func showOpeningAnimation(for appName: String) {
        openingAppName = appName
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { [weak self] in
            Task { @MainActor in
                if self?.openingAppName == appName {
                    self?.openingAppName = nil
                }
            }
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

    private func handleAnimeSourceManagement(_ command: RemoteCommand) {
        switch command {
        case .up:
            animeSourceCatalog.moveFocus(by: -1)
            focusedAnimeSourceID = animeSourceCatalog.focusedID
        case .down:
            animeSourceCatalog.moveFocus(by: 1)
            focusedAnimeSourceID = animeSourceCatalog.focusedID
        case .left:
            cycleFocusedAnimeSourceLine(forward: false)
        case .right:
            cycleFocusedAnimeSourceLine(forward: true)
        case .select:
            guard let focusedAnimeSourceID else {
                return
            }
            animeSourceCatalog.toggleEnabled(sourceID: focusedAnimeSourceID)
            statusMessage = animeSourceStatusMessage(for: focusedAnimeSourceID)
        case .menu:
            animeSourceCatalog.displayMode = animeSourceCatalog.displayMode.next
            statusMessage = animeSourceCatalog.displayMode == .simple ? "來源：簡單模式" : "來源：詳細模式"
        case .rewind:
            moveFocusedAnimeSource(offset: -1)
        case .fastForward:
            moveFocusedAnimeSource(offset: 1)
        case .home, .back:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func cycleFocusedAnimeSourceLine(forward: Bool) {
        guard let focusedAnimeSourceID else {
            return
        }
        animeSourceCatalog.cycleLine(sourceID: focusedAnimeSourceID, forward: forward)
        statusMessage = animeSourceStatusMessage(for: focusedAnimeSourceID)
    }

    private func moveFocusedAnimeSource(offset: Int) {
        guard let focusedAnimeSourceID else {
            return
        }
        animeSourceCatalog.moveSource(sourceID: focusedAnimeSourceID, offset: offset)
        self.focusedAnimeSourceID = animeSourceCatalog.focusedID
    }

    private func animeSourceStatusMessage(for sourceID: String) -> String {
        guard let source = animeSourceCatalog.instance(id: sourceID) else {
            return "動漫來源"
        }
        let line = source.selectedLine?.title ?? "預設線路"
        let enabled = source.isEnabled ? "已啟用" : "已停用"
        return "\(source.definition.title)：\(enabled)，\(line)"
    }
}

private extension ActiveRuntime {
    var handlesBackInternally: Bool {
        switch self {
        case .anime, .youtube:
            return true
        case .animeSourceManagement:
            return true
        default:
            return false
        }
    }
}
