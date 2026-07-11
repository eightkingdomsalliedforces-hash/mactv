import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

public enum LauncherFocus: Equatable, Sendable {
    case apps
    case history
}

public enum ControlCenterFocus: CaseIterable, Equatable, Sendable {
    case home
    case focusMode
    case audio
    case display
    case wallpaper
    case webZoom
    case remote
    case settings

    fileprivate func moved(by command: RemoteCommand) -> ControlCenterFocus {
        let items = Self.allCases
        guard let index = items.firstIndex(of: self) else {
            return self
        }
        let columns = 2
        let nextIndex: Int
        switch command {
        case .left:
            nextIndex = max(0, index - 1)
        case .right:
            nextIndex = min(items.count - 1, index + 1)
        case .up:
            nextIndex = max(0, index - columns)
        case .down:
            nextIndex = min(items.count - 1, index + columns)
        default:
            return self
        }
        return items[nextIndex]
    }
}

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
    @Published public var webRemoteMode: WebRemoteMode = .mouse
    @Published public var webZoom: Double = 1.25
    @Published public var videoSourceLabel: String = "內建示範影片"
    @Published public var dandanplayCredentials: DandanplayCredentials = .environment()
    @Published public var youtubeCredentials: YouTubeCredentials = .environment()
    @Published public var bilibiliCredentials: BilibiliCredentials = .environment()
    @Published public var openingAppName: String?
    @Published public var animeSourceCatalog: AnimeSourceCatalogState
    @Published public var focusedAnimeSourceID: String?
    @Published public var watchingHistory: [WatchHistoryEntry] = []
    @Published public var preferredAnimeStreams: [String: String] = [:]
    @Published public var isControlCenterPresented = false
    @Published public var controlCenterFocus: ControlCenterFocus = .home
    @Published public var isFocusModeEnabled = false
    @Published public var isAudioMuted = false
    @Published public var quickVolume = 0.70
    @Published public var isStatusClockHidden = false
    @Published public private(set) var launcherFocus: LauncherFocus = .apps
    @Published public var focusedWatchHistoryID: UUID?
    @Published public private(set) var pendingWatchHistoryEntry: WatchHistoryEntry?
    @Published public var danmakuDisplaySettings = DanmakuDisplaySettings()
    @Published public var networkRemoteStatus = NetworkRemoteControlStatus(
        isRunning: false,
        urlText: NetworkRemoteControlServer.remoteURLText(),
        message: "網路遙控器尚未啟動"
    )

    private let nativeRuntime = NativeAppRuntime()
    private let networkRemoteServer = NetworkRemoteControlServer.shared
    private let settingsStore: AppSettingsStore?
    private let credentialsStore: AppCredentialsStore?
    private nonisolated(unsafe) var exitObserver: NSObjectProtocol?
    private nonisolated(unsafe) var historyObserver: NSObjectProtocol?
    private nonisolated(unsafe) var animeStreamPreferenceObserver: NSObjectProtocol?
    private nonisolated(unsafe) var statusClockObserver: NSObjectProtocol?

    public init(
        apps: [TVAppProfile] = SeedApps.defaultApps,
        settingsStore: AppSettingsStore? = nil,
        credentialsStore: AppCredentialsStore? = nil,
        startNetworkRemote: Bool = false
    ) {
        self.settingsStore = settingsStore
        self.credentialsStore = credentialsStore
        let loadedSnapshot: AppSettingsSnapshot?
        if let settingsStore {
            loadedSnapshot = try? settingsStore.load()
        } else {
            loadedSnapshot = nil
        }
        let loadedCredentials: AppCredentialsSnapshot?
        if let credentialsStore {
            try? credentialsStore.ensureTemplate()
            loadedCredentials = try? credentialsStore.load()
        } else {
            loadedCredentials = nil
        }
        let restoredApps = loadedSnapshot?.apps.isEmpty == false ? loadedSnapshot?.apps : apps
        self.apps = SeedApps.includingMissingDefaults(in: restoredApps ?? apps, defaults: apps)
        animeSourceCatalog = (loadedSnapshot?.animeSourceCatalog ?? AnimeSourceCatalogState(definitions: AnimeSourceCatalog.defaultSources))
            .includingDefaultSources()
            .removingUnusableSources()
        displayScale = loadedSnapshot?.displayScale ?? .auto
        wallpaperSource = loadedSnapshot?.wallpaperSource ?? .builtIn(.aurora)
        webRemoteMode = loadedSnapshot?.webRemoteMode ?? .mouse
        webZoom = loadedSnapshot?.webZoom ?? 1.25
        videoSourceLabel = loadedSnapshot?.videoSourceLabel ?? "內建示範影片"
        watchingHistory = loadedSnapshot?.watchingHistory ?? []
        preferredAnimeStreams = loadedSnapshot?.preferredAnimeStreams ?? [:]
        danmakuDisplaySettings = loadedSnapshot?.danmakuDisplaySettings ?? DanmakuDisplaySettings()
        youtubeCredentials = Self.resolved(loadedCredentials?.youtube, fallback: .environment())
        dandanplayCredentials = Self.resolved(loadedCredentials?.dandanplay, fallback: .environment())
        bilibiliCredentials = Self.resolved(loadedCredentials?.bilibili, fallback: .environment())
        focusedAppID = self.apps.first?.id
        focusedWatchHistoryID = watchingHistory.first?.id
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
        historyObserver = NotificationCenter.default.addObserver(
            forName: .tvShellRecordWatch,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let entry = notification.userInfo?[WatchHistoryNotification.entryKey] as? WatchHistoryEntry else {
                return
            }
            Task { @MainActor in
                self?.recordWatch(entry)
            }
        }
        animeStreamPreferenceObserver = NotificationCenter.default.addObserver(
            forName: .tvShellRememberAnimeStream,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mediaID = notification.userInfo?[AnimeStreamPreferenceNotification.mediaIDKey] as? String,
                  let streamURL = notification.userInfo?[AnimeStreamPreferenceNotification.streamURLKey] as? String
            else {
                return
            }
            Task { @MainActor in
                self?.preferredAnimeStreams[mediaID] = streamURL
                self?.saveSettings()
            }
        }
        statusClockObserver = NotificationCenter.default.addObserver(
            forName: .tvShellSetStatusClockHidden,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let hidden = notification.userInfo?[StatusClockNotification.hiddenKey] as? Bool else {
                return
            }
            Task { @MainActor in
                self?.isStatusClockHidden = hidden
            }
        }
        if startNetworkRemote {
            startNetworkRemoteServer()
        }
    }

    deinit {
        if let exitObserver {
            NotificationCenter.default.removeObserver(exitObserver)
        }
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
        if let animeStreamPreferenceObserver {
            NotificationCenter.default.removeObserver(animeStreamPreferenceObserver)
        }
        if let statusClockObserver {
            NotificationCenter.default.removeObserver(statusClockObserver)
        }
    }

    public func resumeTime(for mediaID: String) -> Double? {
        watchingHistory.first { $0.mediaID == mediaID }?.resumeTimeSeconds
    }

    public func recordWatchForTesting(_ entry: WatchHistoryEntry) {
        recordWatch(entry)
    }

    public func deleteWatchHistory(_ entry: WatchHistoryEntry) {
        watchingHistory.removeAll { existing in
            if let mediaID = entry.mediaID {
                return existing.mediaID == mediaID
            }
            return existing.id == entry.id
        }
        focusedWatchHistoryID = watchingHistory.first?.id
        if watchingHistory.isEmpty {
            launcherFocus = .apps
        }
        saveSettings()
        statusMessage = "已刪除最近觀看：\(entry.title)"
    }

    public func clearWatchingHistory() {
        watchingHistory.removeAll()
        focusedWatchHistoryID = nil
        launcherFocus = .apps
        saveSettings()
        statusMessage = "已清除最近觀看"
    }

    public func startNetworkRemoteServer() {
        networkRemoteStatus = networkRemoteServer.start { [weak self] command in
            Task { @MainActor in
                self?.handle(command)
            }
        }
    }

    private func recordWatch(_ entry: WatchHistoryEntry) {
        watchingHistory.removeAll { existing in
            if let mediaID = entry.mediaID {
                return existing.mediaID == mediaID
            }
            return existing.title == entry.title && existing.kind == entry.kind
        }
        watchingHistory.insert(entry, at: 0)
        if watchingHistory.count > 24 {
            watchingHistory = Array(watchingHistory.prefix(24))
        }
        if focusedWatchHistoryID == nil {
            focusedWatchHistoryID = entry.id
        }
        saveSettings()
    }

    public func saveSettings() {
        guard let settingsStore else {
            return
        }
        let snapshot = AppSettingsSnapshot(
            apps: apps,
            displayScale: displayScale,
            wallpaperSource: wallpaperSource,
            webRemoteMode: webRemoteMode,
            webZoom: webZoom,
            videoSourceLabel: videoSourceLabel,
            animeSourceCatalog: animeSourceCatalog,
            watchingHistory: watchingHistory,
            danmakuDisplaySettings: danmakuDisplaySettings,
            preferredAnimeStreams: preferredAnimeStreams
        )
        try? settingsStore.save(snapshot)
    }

    public var credentialsFilePath: String {
        (credentialsStore ?? .applicationSupport()).fileURL.path
    }

    public func reloadCredentials() {
        guard let credentialsStore else {
            statusMessage = "此版本未設定 credentials store"
            return
        }
        do {
            try credentialsStore.ensureTemplate()
            if let snapshot = try credentialsStore.load() {
                youtubeCredentials = Self.resolved(snapshot.youtube, fallback: .environment())
                dandanplayCredentials = Self.resolved(snapshot.dandanplay, fallback: .environment())
                bilibiliCredentials = Self.resolved(snapshot.bilibili, fallback: .environment())
            }
            statusMessage = "已重載憑證：\(credentialsStore.fileURL.path)"
        } catch {
            statusMessage = "憑證讀取失敗：\(error.localizedDescription)"
        }
    }

    private static func resolved(_ fileCredentials: YouTubeCredentials?, fallback: YouTubeCredentials) -> YouTubeCredentials {
        fileCredentials?.isConfigured == true ? fileCredentials! : fallback
    }

    private static func resolved(_ fileCredentials: DandanplayCredentials?, fallback: DandanplayCredentials) -> DandanplayCredentials {
        fileCredentials?.isConfigured == true ? fileCredentials! : fallback
    }

    private static func resolved(_ fileCredentials: BilibiliCredentials?, fallback: BilibiliCredentials) -> BilibiliCredentials {
        fileCredentials?.isConfigured == true ? fileCredentials! : fallback
    }

    public func handle(_ command: RemoteCommand) {
        lastCommand = command

        if command == .longPress(.menu) {
            isControlCenterPresented.toggle()
            statusMessage = isControlCenterPresented ? "控制中心" : nil
            return
        }

        if isControlCenterPresented {
            handleControlCenter(command)
            return
        }

        switch command {
        case .volumeUp:
            adjustQuickVolume(0.05)
        case .volumeDown:
            adjustQuickVolume(-0.05)
        case .mute:
            toggleQuickMute()
        default:
            break
        }

        switch activeRuntime {
        case .launcher:
            handleLauncher(command)
        case .settings:
            handleSettings(command)
        case .appManagement:
            handleAppManagement(command)
        case .animeSourceManagement:
            handleAnimeSourceManagement(command)
        case .web, .media, .anime, .youtube, .bilibili, .native, .remoteLearning:
            handleRuntimeCommand(command)
        }
    }

    private func handleControlCenter(_ command: RemoteCommand) {
        switch command {
        case .left, .right:
            if controlCenterFocus == .audio {
                adjustQuickVolume(command == .right ? 0.05 : -0.05)
            } else {
                controlCenterFocus = controlCenterFocus.moved(by: command)
            }
        case .up, .down:
            controlCenterFocus = controlCenterFocus.moved(by: command)
        case .volumeUp:
            adjustQuickVolume(0.05)
        case .volumeDown:
            adjustQuickVolume(-0.05)
        case .mute:
            toggleQuickMute()
        case .select:
            activateControlCenterItem()
        case .back, .menu, .home:
            isControlCenterPresented = false
        default:
            break
        }
    }

    private func activateControlCenterItem() {
        switch controlCenterFocus {
        case .home:
            activeRuntime = .launcher
            isControlCenterPresented = false
        case .focusMode:
            isFocusModeEnabled.toggle()
        case .audio:
            toggleQuickMute()
        case .display:
            displayScale = displayScale.next
            saveSettings()
        case .wallpaper:
            let preset = wallpaperSource.preset ?? .aurora
            wallpaperSource = .builtIn(preset.next)
            saveSettings()
        case .webZoom:
            webZoom = webZoom >= 2 ? 1 : min(webZoom + 0.25, 2)
            saveSettings()
        case .remote:
            if networkRemoteStatus.isRunning == false {
                startNetworkRemoteServer()
            }
            statusMessage = networkRemoteStatus.message
        case .settings:
            isControlCenterPresented = false
            setRuntime(.settings)
        }
    }

    private func adjustQuickVolume(_ amount: Double) {
        quickVolume = min(max(quickVolume + amount, 0), 1)
        if quickVolume > 0 {
            isAudioMuted = false
        }
        SystemVolumeController.apply(volume: quickVolume, isMuted: isAudioMuted)
    }

    private func toggleQuickMute() {
        isAudioMuted.toggle()
        SystemVolumeController.apply(volume: quickVolume, isMuted: isAudioMuted)
    }

    private func handleLauncher(_ command: RemoteCommand) {
        switch command {
        case .left:
            moveLauncherFocusHorizontally(command)
        case .right:
            moveLauncherFocusHorizontally(command)
        case .up:
            if launcherFocus == .history {
                launcherFocus = .apps
            } else {
                moveFocusedApp(command)
            }
        case .down:
            if launcherFocus == .apps, watchingHistory.isEmpty == false {
                launcherFocus = .history
                focusedWatchHistoryID = focusedWatchHistoryID ?? watchingHistory.first?.id
            } else if launcherFocus == .apps {
                moveFocusedApp(command)
            }
        case .select:
            if launcherFocus == .history, let entry = focusedWatchHistoryEntry {
                openWatchHistory(entry)
            } else {
                openFocusedApp()
            }
        case .menu:
            if launcherFocus == .history, let entry = focusedWatchHistoryEntry {
                deleteWatchHistory(entry)
            } else if watchingHistory.isEmpty == false {
                clearWatchingHistory()
            }
        case .home:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private var focusedWatchHistoryEntry: WatchHistoryEntry? {
        guard let focusedWatchHistoryID else {
            return watchingHistory.first
        }
        return watchingHistory.first { $0.id == focusedWatchHistoryID } ?? watchingHistory.first
    }

    private func moveLauncherFocusHorizontally(_ command: RemoteCommand) {
        guard launcherFocus == .history else {
            moveFocusedApp(command)
            return
        }
        guard watchingHistory.isEmpty == false else {
            launcherFocus = .apps
            return
        }
        let currentIndex = watchingHistory.firstIndex { $0.id == focusedWatchHistoryID } ?? 0
        let delta = command == .left ? -1 : 1
        let nextIndex = min(max(currentIndex + delta, 0), watchingHistory.count - 1)
        focusedWatchHistoryID = watchingHistory[nextIndex].id
    }

    public func openWatchHistory(_ entry: WatchHistoryEntry) {
        guard let app = appForWatchHistory(entry) else {
            statusMessage = "找不到可用的續播 App。"
            return
        }
        pendingWatchHistoryEntry = entry
        focusedAppID = app.id
        open(app)
    }

    public func consumePendingWatchHistory(kind: WatchHistoryKind) -> WatchHistoryEntry? {
        guard pendingWatchHistoryEntry?.kind == kind else {
            return nil
        }
        defer { pendingWatchHistoryEntry = nil }
        return pendingWatchHistoryEntry
    }

    private func appForWatchHistory(_ entry: WatchHistoryEntry) -> TVAppProfile? {
        apps.first { app in
            switch (entry.kind, app.target) {
            case (.anime, .anime), (.youtube, .youtube), (.bilibili, .bilibili), (.media, .media), (.web, .web):
                true
            default:
                false
            }
        }
    }

    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home || (command == .back && activeRuntime.handlesBackInternally == false) {
            activeRuntime = .launcher
            isStatusClockHidden = false
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if case .web = activeRuntime, command == .menu {
            webRemoteMode = webRemoteMode.next
            saveSettings()
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
            if settingsFocus.isAdjustable {
                changeFocusedSetting(previous: true)
            }
        case .right:
            if settingsFocus.isAdjustable {
                changeFocusedSetting(previous: false)
            }
        case .select:
            if settingsFocus.isAdjustable == false {
                changeFocusedSetting(previous: false)
            }
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
        case .danmakuSize:
            danmakuDisplaySettings = danmakuDisplaySettings.adjusted(previous: previous)
        case .danmakuSpeed:
            danmakuDisplaySettings = danmakuDisplaySettings.adjustedSpeed(previous: previous)
        case .danmakuOpacity:
            danmakuDisplaySettings = danmakuDisplaySettings.adjustedOpacity(previous: previous)
        case .danmakuDensity:
            danmakuDisplaySettings = danmakuDisplaySettings.adjustedDensity(previous: previous)
        case .videoSource:
            chooseVideoFile()
            return
        case .credentials:
            reloadCredentials()
            return
        }
        saveSettings()
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
        saveSettings()
    }

    private func moveFocusedApp(_ command: RemoteCommand) {
        // The tvOS home uses one horizontal dock, so focus must follow the
        // same visible sequence rather than the legacy grouped launcher rows.
        let visibleApps = apps.filter(\.isVisibleOnHome)
        guard visibleApps.isEmpty == false else {
            focusedAppID = nil
            return
        }
        guard let focusedAppID,
              let currentIndex = visibleApps.firstIndex(where: { $0.id == focusedAppID })
        else {
            self.focusedAppID = visibleApps.first?.id
            return
        }

        switch command {
        case .left:
            self.focusedAppID = visibleApps[max(0, currentIndex - 1)].id
        case .right:
            self.focusedAppID = visibleApps[min(visibleApps.count - 1, currentIndex + 1)].id
        default:
            break
        }
    }

    private func openFocusedApp() {
        guard let app = apps.first(where: { $0.id == focusedAppID }) else {
            return
        }

        open(app)
    }

    private func open(_ app: TVAppProfile) {
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
        case .bilibili:
            statusMessage = "正在開啟 \(app.name)"
            setRuntime(.bilibili(app))
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
                saveSettings()
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
        saveSettings()
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
            guard animeSourceCatalog.instance(id: focusedAnimeSourceID)?.definition.health.canToggleFromRemote == true else {
                statusMessage = animeSourceUnavailableMessage(for: focusedAnimeSourceID)
                return
            }
            animeSourceCatalog.toggleEnabled(sourceID: focusedAnimeSourceID)
            statusMessage = animeSourceStatusMessage(for: focusedAnimeSourceID)
            saveSettings()
        case .menu:
            animeSourceCatalog.displayMode = animeSourceCatalog.displayMode.next
            statusMessage = animeSourceCatalog.displayMode == .simple ? "來源：簡單模式" : "來源：詳細模式"
            saveSettings()
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
        saveSettings()
    }

    private func moveFocusedAnimeSource(offset: Int) {
        guard let focusedAnimeSourceID else {
            return
        }
        animeSourceCatalog.moveSource(sourceID: focusedAnimeSourceID, offset: offset)
        self.focusedAnimeSourceID = animeSourceCatalog.focusedID
        saveSettings()
    }

    private func animeSourceStatusMessage(for sourceID: String) -> String {
        guard let source = animeSourceCatalog.instance(id: sourceID) else {
            return "動漫來源"
        }
        let line = source.selectedLine?.title ?? "預設線路"
        let enabled = source.isEnabled ? "已啟用" : "已停用"
        return "\(source.definition.title)：\(enabled)，\(line)"
    }

    private func animeSourceUnavailableMessage(for sourceID: String) -> String {
        guard let source = animeSourceCatalog.instance(id: sourceID) else {
            return "動漫來源不可用"
        }

        switch source.definition.health {
        case .needsAdapter:
            return "\(source.definition.title)：待接入 adapter，目前不能播放"
        case .needsCloudflare:
            return "\(source.definition.title)：需要 Cloudflare 驗證流程"
        case .needsCaptcha:
            return "\(source.definition.title)：需要驗證碼流程"
        case .failed:
            return "\(source.definition.title)：目前連線失敗"
        case .loading:
            return "\(source.definition.title)：正在等待健康檢查"
        case .disabled:
            return "\(source.definition.title)：已停用"
        case .available:
            return animeSourceStatusMessage(for: sourceID)
        }
    }
}

private extension AnimeSourceHealth {
    var canToggleFromRemote: Bool {
        switch self {
        case .available:
            true
        case .loading, .failed, .needsCloudflare, .needsCaptcha, .needsAdapter, .disabled:
            false
        }
    }
}

private extension ActiveRuntime {
    var handlesBackInternally: Bool {
        switch self {
        case .anime, .youtube, .bilibili:
            return true
        case .animeSourceManagement:
            return true
        default:
            return false
        }
    }
}
