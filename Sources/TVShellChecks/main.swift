import CoreGraphics
import Foundation
import TVShellCore

private enum KeywordAnimeSourceError: Error {
    case failingKeyword
}

private struct KeywordAnimeSourceProvider: AnimeMediaSourceAdapter {
    let id: String
    let displayName: String
    let resolverKind: AnimeResolverKind
    private let resultsByKeyword: [String: [AnimeSearchResult]]
    private let streamCandidates: [String: [AnimeStreamCandidate]]
    private let failingKeywords: Set<String>

    init(
        id: String,
        displayName: String,
        resultsByKeyword: [String: [AnimeSearchResult]],
        streams: [String: [AnimeStreamCandidate]] = [:],
        failingKeywords: Set<String> = [],
        resolverKind: AnimeResolverKind = .http
    ) {
        self.id = id
        self.displayName = displayName
        self.resultsByKeyword = resultsByKeyword
        self.streamCandidates = streams
        self.failingKeywords = failingKeywords
        self.resolverKind = resolverKind
    }

    func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if failingKeywords.contains(keyword) {
            throw KeywordAnimeSourceError.failingKeyword
        }
        return resultsByKeyword[keyword] ?? []
    }

    func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes.sorted { $0.number < $1.number }
    }

    func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        (streamCandidates[episode.id] ?? []).sorted { $0.priority > $1.priority }
    }
}

private final class HandlerAnimeHTTPTransport: AnimeHTTPTransport, @unchecked Sendable {
    private let handler: (AnimeHTTPRequest) throws -> Data

    init(handler: @escaping (AnimeHTTPRequest) throws -> Data) {
        self.handler = handler
    }

    func data(for request: AnimeHTTPRequest) async throws -> Data {
        try handler(request)
    }
}

@main
struct TVShellChecks {
    static func main() async throws {
        try checkKeyCodeMapper()
        try checkVirtualKeyboardState()
        try checkRemoteMappingStore()
        try checkFocusEngine()
        try checkNativeLaunchRequest()
        try checkDisplayScale()
        try checkMediaControlState()
        try checkSeedAppsIncludeMediaAndSettings()
        try checkLauncherLayoutNavigation()
        try checkAppStateOpensFocusedApps()
        try checkTVMetricsScaleWithWindowSize()
        try checkAppCatalogVisibilityAndOrdering()
        try checkSettingsPersistAcrossRelaunch()
        try checkWatchHistoryMergesByMediaID()
        try checkWallpaperPresetCyclingAndProvider()
        try checkQuickActionsAndBrowserArePresent()
        try checkWebRemoteModeCycles()
        try checkWebRuntimeShowsVirtualCursor()
        try checkSettingsFocusIncludesVideoAndWebZoom()
        try await checkAnimeSourceAndDanmakuProviders()
        try checkAnimeRuntimeStateNavigation()
        try checkExternalAnimeIntegrations()
        try await checkDandanplayConfiguredProvider()
        try await checkDandanplaySearchEpisodesFallback()
        try checkYouTubeNativeRuntimeAndAPI()
        try checkYouTubeEmbedPageIncludesOriginAndFallback()
        try checkYouTubeLayoutAndPlayerShell()
        try await checkBangumiYouTubeAnimeSourceFindsPlayableCandidates()
        try await checkBuiltInAnimekoStyleSources()
        try await checkAniSubsBTSubscriptionProvider()
        try checkAnimeEpisodeGridLayout()
        try checkTorrentPlaybackEngine()
        try await checkAnimeHomeProviderAggregatesDistinctTitles()
        try checkAnimekoStyleSourceCatalog()
        try await checkAnimeSourceRegistryUsesCatalog()
        try await checkCatalogAnimeSourceProviderAggregatesResults()
        try await checkSelectorAnimeSourceProvider()
        try checkAnimeSourcesExposePlayableStatusAndSearchChoices()
        try checkBigScreenViewsStayScrollableAndWindowIsResizable()
        try checkRuntimeNavigationAndPerformanceBudget()
        try checkGitHubReleaseWorkflow()
        print("TVShellChecks passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw CheckFailure(message)
        }
    }

    static func checkKeyCodeMapper() throws {
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 126, characters: nil, modifiers: [])) == .up, "up arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 125, characters: nil, modifiers: [])) == .down, "down arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 123, characters: nil, modifiers: [])) == .left, "left arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 124, characters: nil, modifiers: [])) == .right, "right arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 36, characters: "\r", modifiers: [])) == .select, "return maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 53, characters: "\u{1b}", modifiers: [])) == .back, "escape maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 4, characters: "h", modifiers: [.command])) == .home, "command-h maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 49, characters: " ", modifiers: [])) == .playPause, "space maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 8, characters: "c", modifiers: [])) == nil, "unknown remains nil")
        try expect(KeyCodeMapper.default.command(for: .media(systemCode: 17)) == .fastForward, "media next maps to fastForward")
        try expect(KeyCodeMapper.default.command(for: .media(systemCode: 18)) == .rewind, "media previous maps to rewind")
        try expect(KeyCodeMapper.default.command(for: .hid(usagePage: 0x0C, usage: 0x223)) == .home, "HID AC Home maps")
        try expect(KeyCodeMapper.default.command(for: .hid(usagePage: 0x0C, usage: 0x224)) == .back, "HID AC Back maps")
        try expect(KeyCodeMapper.default.command(for: .hid(usagePage: 0x0C, usage: 0x40)) == .menu, "HID menu maps")
        try expect(KeyCodeMapper.default.command(for: .hid(usagePage: 0x0C, usage: 0x41)) == .select, "HID select maps")
    }

    static func checkVirtualKeyboardState() throws {
        var keyboard = VirtualKeyboardState()
        try expect(keyboard.focusedKey.label == "1", "virtual keyboard starts at first key")
        try expect(keyboard.apply(.right) == .none, "virtual keyboard right moves focus")
        try expect(keyboard.focusedKey.label == "2", "virtual keyboard focuses next key")
        try expect(keyboard.apply(.select) == .textChanged, "virtual keyboard select types focused key")
        try expect(keyboard.text == "2", "virtual keyboard appends key text")
        try expect(keyboard.apply(.back) == .textChanged, "virtual keyboard back deletes text")
        try expect(keyboard.text.isEmpty, "virtual keyboard delete leaves empty text")
        try expect(keyboard.apply(.back) == .cancelled, "virtual keyboard back cancels when empty")

        var submitKeyboard = VirtualKeyboardState(text: "frieren")
        _ = submitKeyboard.apply(.down)
        _ = submitKeyboard.apply(.down)
        _ = submitKeyboard.apply(.down)
        _ = submitKeyboard.apply(.down)
        _ = submitKeyboard.apply(.right)
        _ = submitKeyboard.apply(.right)
        try expect(submitKeyboard.focusedKey.label == "搜尋", "virtual keyboard can focus submit")
        try expect(submitKeyboard.apply(.select) == .submitted("frieren"), "virtual keyboard submits current text")

        var zhuyinKeyboard = VirtualKeyboardState(layout: .zhuyin)
        try expect(zhuyinKeyboard.focusedKey.label == "ㄅ", "zhuyin keyboard starts at bopomofo keys")
        try expect(zhuyinKeyboard.apply(.select) == .textChanged, "zhuyin keyboard types focused bopomofo key")
        try expect(zhuyinKeyboard.composition == "ㄅ", "zhuyin keyboard keeps bopomofo composition")
        try expect(zhuyinKeyboard.candidates.contains("不"), "zhuyin keyboard exposes Chinese candidates")
        try expect(zhuyinKeyboard.text.isEmpty, "zhuyin keyboard does not commit raw bopomofo immediately")
        try expect(zhuyinKeyboard.apply(.select) == .textChanged, "zhuyin keyboard commits the focused candidate")
        try expect(zhuyinKeyboard.text == "不", "zhuyin keyboard commits Chinese text")
        _ = zhuyinKeyboard.apply(.down)
        _ = zhuyinKeyboard.apply(.down)
        _ = zhuyinKeyboard.apply(.down)
        _ = zhuyinKeyboard.apply(.down)
        _ = zhuyinKeyboard.apply(.down)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        _ = zhuyinKeyboard.apply(.right)
        try expect(zhuyinKeyboard.focusedKey.label == "ABC", "zhuyin keyboard exposes ABC switch")
        try expect(zhuyinKeyboard.apply(.select) == .none, "layout switch does not submit text")
        try expect(zhuyinKeyboard.layout == .latin, "zhuyin keyboard switches back to latin")

        var phraseKeyboard = VirtualKeyboardState(layout: .zhuyin)
        phraseKeyboard.typeZhuyinForTesting("ㄈㄨˊ")
        try expect(phraseKeyboard.candidates.first == "芙", "zhuyin keyboard suggests anime search characters")
        _ = phraseKeyboard.apply(.select)
        phraseKeyboard.typeZhuyinForTesting("ㄌㄧˋ")
        _ = phraseKeyboard.apply(.select)
        phraseKeyboard.typeZhuyinForTesting("ㄌㄧㄢˊ")
        _ = phraseKeyboard.apply(.select)
        try expect(phraseKeyboard.text == "芙莉蓮", "zhuyin keyboard can compose a Chinese anime title")

        var cocoaKeyboard = VirtualKeyboardState(layout: .zhuyin)
        cocoaKeyboard.typeZhuyinForTesting("ㄎㄜˇ")
        try expect(cocoaKeyboard.candidates.first == "可", "zhuyin keyboard suggests common Chinese syllables")
        _ = cocoaKeyboard.apply(.select)
        cocoaKeyboard.typeZhuyinForTesting("ㄎㄜˇ")
        _ = cocoaKeyboard.apply(.select)
        try expect(cocoaKeyboard.text == "可可", "zhuyin keyboard can compose repeated Chinese syllables")

        try expect(ZhuyinComposer.candidates(for: "ㄎㄧㄚˇ").first == "卡", "zhuyin keyboard tolerates common non-standard ka input")
        try expect(ZhuyinComposer.candidates(for: "ㄓㄨˋㄧㄣ").first == "注音", "zhuyin keyboard composes multi-syllable words")
        try expect(ZhuyinComposer.candidates(for: "ㄎㄜˇㄎㄜˇ").first == "可可", "zhuyin keyboard segments repeated syllables")
        try expect(ZhuyinComposer.candidates(for: "ㄉㄧㄢˋ").first == "電", "zhuyin keyboard suggests dian fourth tone as electric")
        try expect(ZhuyinComposer.candidates(for: "ㄨㄛˇ").contains("我"), "zhuyin keyboard includes basic pronouns")
        try expect(ZhuyinComposer.candidates(for: "ㄕˋ").contains("是"), "zhuyin keyboard includes basic verbs")
        try expect(ZhuyinComposer.candidates(for: "ㄋㄧˇ").contains("你"), "zhuyin keyboard includes common second-person pronouns")
        try expect(ZhuyinComposer.candidates(for: "ㄗㄞˋ").contains("在"), "zhuyin keyboard includes common location verbs")
        try expect(ZhuyinComposer.candidates(for: "ㄎㄢˋ").contains("看"), "zhuyin keyboard includes common media search verbs")
        try expect(ZhuyinComposer.candidates(for: "ㄕㄨㄛ").contains("說"), "zhuyin keyboard includes common speaking verbs")
        try expect(ZhuyinComposer.candidates(for: "ㄌㄠˇㄕ").first == "老師", "zhuyin keyboard composes common two-syllable words")
        try expect(ZhuyinComposer.candidates(for: "ㄒㄩㄝˊㄕㄥ").first == "學生", "zhuyin keyboard composes basic study words")
        try expect(ZhuyinComposer.candidates(for: "ㄨㄤˇㄌㄨˋ").first == "網路", "zhuyin keyboard composes common internet words")
        try expect(ZhuyinComposer.candidates(for: "ㄉㄧㄢˋㄧㄥˇ").first == "電影", "zhuyin keyboard composes common media words")
        try expect(ZhuyinComposer.candidates(for: "ㄅㄚ").contains("八"), "zhuyin keyboard loads basic candidates from chewing data")
        try expect(ZhuyinComposer.candidates(for: "ㄅㄚˋ").contains("爸"), "zhuyin keyboard loads tone-specific candidates from chewing data")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let chewingDictionary = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Input/ZhuyinChewingDictionary.swift"))
        try expect(chewingDictionary.contains("LGPL-2.1-or-later"), "chewing zhuyin dictionary keeps source license notice")
        try expect(chewingDictionary.contains("libchewing-data"), "chewing zhuyin dictionary keeps source project notice")

        var candidateKeyboard = VirtualKeyboardState(layout: .zhuyin)
        candidateKeyboard.typeZhuyinForTesting("ㄉㄧㄢˋ")
        try expect(candidateKeyboard.visibleCandidates.prefix(2) == ["電", "店"], "zhuyin keyboard exposes multiple selectable candidates")
        try expect(candidateKeyboard.apply(.up) == .none, "zhuyin keyboard moves focus into candidate row")
        try expect(candidateKeyboard.focusedCandidateIndex == 0, "zhuyin keyboard focuses first candidate")
        try expect(candidateKeyboard.apply(.right) == .none, "zhuyin keyboard moves across candidates")
        try expect(candidateKeyboard.focusedCandidateIndex == 1, "zhuyin keyboard focuses next candidate")
        try expect(candidateKeyboard.apply(.select) == .textChanged, "zhuyin keyboard commits selected candidate")
        try expect(candidateKeyboard.text == "店", "zhuyin keyboard commits the focused candidate rather than always the first one")
    }

    static func checkRemoteMappingStore() throws {
        var store = RemoteMappingStore()
        let raw = RawInputEvent.keyboard(keyCode: 8, characters: "c", modifiers: [])

        try expect(store.command(for: raw) == nil, "unknown command before learning")
        store.learn(raw, as: .home)
        try expect(store.command(for: raw) == .home, "learned mapping overrides unknown input")

        let hid = RawInputEvent.hid(usagePage: 12, usage: 999)
        store.learn(hid, as: .back)
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(RemoteMappingStore.self, from: data)
        try expect(decoded.command(for: hid) == .back, "mappings round-trip through JSON")
    }

    static func checkFocusEngine() throws {
        var engine = FocusEngine()
        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 140, y: 180, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")
        try expect(engine.move(.right) == "b", "right moves to nearest same row candidate")

        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 20, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 280, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")
        try expect(engine.move(.down) == "b", "down moves to nearest vertical candidate")

        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 1, acceptsSelect: true)
        ])
        try expect(engine.recoverFocus(in: "home") == "b", "recover chooses highest-priority visible node")
    }

    static func checkNativeLaunchRequest() throws {
        let nativeProfile = TVAppProfile(
            name: "Safari",
            target: .nativeApp(bundleIdentifier: "com.apple.Safari"),
            controlMode: .hybridNative
        )
        try expect(NativeLaunchRequest(profile: nativeProfile)?.bundleIdentifier == "com.apple.Safari", "native launch request uses bundle identifier")

        let webProfile = TVAppProfile(
            name: "Apple",
            target: .web(URL(string: "https://www.apple.com")!),
            controlMode: .web
        )
        try expect(NativeLaunchRequest(profile: webProfile) == nil, "web profile does not create native launch request")
    }

    static func checkDisplayScale() throws {
        try expect(DisplayScale.auto.multiplier(forScreenScale: 1.0) == 1.0, "auto scale uses 1x for normal screen scale")
        try expect(DisplayScale.auto.multiplier(forScreenScale: 2.0) == 1.5, "auto scale grows on high-density screens")
        try expect(DisplayScale.percent125.next == .percent150, "scale cycles forward")
        try expect(DisplayScale.percent125.previous == .percent100, "scale cycles backward")
    }

    static func checkMediaControlState() throws {
        var state = MediaControlState()
        state.apply(.playPause)
        try expect(state.isPlaying, "playPause starts playback")
        state.apply(.select)
        try expect(state.isPlaying == false, "OK toggles playback after the HUD has gone away")
        state.apply(.select, restartOnSelect: true)
        try expect(state.shouldRestartFromBeginning, "OK restarts playback from the beginning while the HUD is visible")
        state.apply(.right)
        try expect(state.pendingSeekOffset == 10, "right seeks forward")
        state.apply(.rewind)
        try expect(state.pendingSeekOffset == -10, "rewind seeks backward")
        state.apply(.back)
        try expect(state.shouldExit, "back exits media runtime")
    }

    static func checkSeedAppsIncludeMediaAndSettings() throws {
        try expect(SeedApps.defaultApps.contains { app in
            if case .media = app.target { return true }
            return false
        }, "seed apps include media runtime")

        try expect(SeedApps.defaultApps.contains { app in
            if case .anime = app.target { return true }
            return false
        }, "seed apps include anime runtime")

        try expect(SeedApps.defaultApps.contains { app in
            if case let .web(url) = app.target { return url.host == "settings" }
            return false
        }, "seed apps include settings runtime")
    }

    static func checkLauncherLayoutNavigation() throws {
        let sections = LauncherLayout.sections(for: SeedApps.defaultApps)
        try expect(sections.count >= 3, "launcher groups apps into multiple tvOS-style rows")

        let firstApp = sections[0].apps[0]
        let below = LauncherLayout.focusedApp(after: .down, currentID: firstApp.id, sections: sections)
        try expect(below == sections[1].apps[0].id, "down moves to first item in next row")

        let right = LauncherLayout.focusedApp(after: .right, currentID: sections[1].apps[0].id, sections: sections)
        try expect(right == sections[1].apps[1].id, "right moves within current row")
    }

    @MainActor
    static func checkAppStateOpensFocusedApps() throws {
        let apps = SeedApps.defaultApps
        let media = apps.first { app in
            if case .media = app.target { return true }
            return false
        }
        guard let media else {
            throw CheckFailure("missing media seed app")
        }

        let state = AppState(apps: apps)
        state.focusedAppID = media.id
        state.handle(.select)
        try expect(state.activeRuntime == .media(media), "select opens focused media app")

        let settings = apps.first { app in
            if case let .web(url) = app.target { return url.host == "settings" }
            return false
        }
        guard let settings else {
            throw CheckFailure("missing settings seed app")
        }

        state.activeRuntime = .launcher
        state.focusedAppID = settings.id
        state.handle(.select)
        try expect(state.activeRuntime == .settings, "select opens focused settings app")

        let anime = apps.first { app in
            if case .anime = app.target { return true }
            return false
        }
        guard let anime else {
            throw CheckFailure("missing anime seed app")
        }

        state.activeRuntime = .launcher
        state.focusedAppID = anime.id
        state.handle(.select)
        try expect(state.activeRuntime == .anime(anime), "select opens focused anime app")
    }

    static func checkTVMetricsScaleWithWindowSize() throws {
        try expect(TVMetrics(size: CGSize(width: 1920, height: 1080)).scale == 1.0, "1080p uses base scale")
        try expect(TVMetrics(size: CGSize(width: 960, height: 540)).scale == 0.72, "small windows clamp to readable minimum")
        try expect(TVMetrics(size: CGSize(width: 3840, height: 2160)).scale == 1.65, "large windows clamp to practical maximum")
    }

    static func checkAppCatalogVisibilityAndOrdering() throws {
        var catalog = AppCatalog(apps: SeedApps.defaultApps)
        let first = catalog.apps[0]
        catalog.toggleVisibility(for: first.id)
        try expect(catalog.visibleApps.contains(where: { $0.id == first.id }) == false, "hidden app is removed from visible launcher apps")

        let second = catalog.apps[1]
        catalog.moveApp(id: second.id, direction: .left)
        try expect(catalog.apps[0].id == second.id, "app can move left in catalog")
    }

    @MainActor
    static func checkSettingsPersistAcrossRelaunch() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TVShellChecks-Settings-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = AppSettingsStore(fileURL: file)
        let state = AppState(apps: SeedApps.defaultApps, settingsStore: store)
        state.displayScale = .percent150
        state.wallpaperSource = .builtIn(.ocean)
        state.webRemoteMode = .scroll
        state.webZoom = 1.7
        state.videoSourceLabel = "收藏影片.mkv"
        state.watchingHistory = [
            WatchHistoryEntry(
                title: "葬送的芙莉蓮",
                subtitle: "第 1 話",
                kind: .anime,
                mediaID: "anime:frieren:1",
                resumeTimeSeconds: 125
            )
        ]
        state.saveSettings()

        let restored = AppState(apps: SeedApps.defaultApps, settingsStore: store)
        try expect(restored.displayScale == .percent150, "display scale persists")
        try expect(restored.wallpaperSource == .builtIn(.ocean), "wallpaper setting persists")
        try expect(restored.webRemoteMode == .scroll, "web remote mode persists")
        try expect(restored.webZoom == 1.7, "web zoom persists")
        try expect(restored.videoSourceLabel == "收藏影片.mkv", "video source label persists")
        try expect(restored.watchingHistory.first?.title == "葬送的芙莉蓮", "watch history persists")
        try expect(restored.watchingHistory.first?.resumeTimeLabel == "02:05", "watch history persists exact playback time")
        try expect(restored.resumeTime(for: "anime:frieren:1") == 125, "app state can look up resume time by media id")
    }

    @MainActor
    static func checkWatchHistoryMergesByMediaID() throws {
        let state = AppState(apps: SeedApps.defaultApps)
        state.recordWatchForTesting(WatchHistoryEntry(
            title: "葬送的芙莉蓮",
            subtitle: "第 1 話",
            kind: .anime,
            mediaID: "anime:frieren:1",
            resumeTimeSeconds: 60
        ))
        state.recordWatchForTesting(WatchHistoryEntry(
            title: "葬送的芙莉蓮",
            subtitle: "第 1 話",
            kind: .anime,
            mediaID: "anime:frieren:1",
            resumeTimeSeconds: 185
        ))
        try expect(state.watchingHistory.count == 1, "watch history merges the same media id")
        try expect(state.watchingHistory.first?.resumeTimeLabel == "03:05", "watch history stores minutes and seconds")
    }

    static func checkWallpaperPresetCyclingAndProvider() throws {
        try expect(WallpaperPreset.aurora.next == .ocean, "wallpaper cycles forward")
        try expect(WallpaperPreset.ocean.previous == .aurora, "wallpaper cycles backward")

        let provider = StaticWallpaperProvider(presets: [.aurora, .ocean])
        try expect(provider.featured().preset == .aurora, "static provider returns first featured wallpaper")
        try expect(provider.next(after: .aurora).preset == .ocean, "static provider returns next wallpaper")
    }

    static func checkQuickActionsAndBrowserArePresent() throws {
        let toolHosts = LauncherLayout.sections(for: SeedApps.defaultApps)
            .first { $0.id == "tools" }?
            .apps
            .compactMap { app -> String? in
                if case let .web(url) = app.target { return url.host }
                return nil
            } ?? []
        try expect(toolHosts.contains("settings"), "settings remains available in the launcher tools row")
        try expect(toolHosts.contains("remote-learning"), "remote setup remains available in the launcher tools row")
        try expect(toolHosts.contains("app-management"), "app management remains available in the launcher tools row")

        try expect(SeedApps.defaultApps.contains { app in
            if case let .web(url) = app.target { return url.host == "duckduckgo.com" }
            return false
        }, "embedded browser app exists")
    }

    static func checkWebRemoteModeCycles() throws {
        try expect(WebRemoteMode.keyboard.next == .domFocus, "web remote mode cycles from keyboard to DOM focus")
        try expect(WebRemoteMode.domFocus.next == .scroll, "web remote mode cycles from DOM focus to scroll")
        try expect(WebRemoteMode.scroll.next == .mouse, "web remote mode cycles from scroll to mouse")
        try expect(WebRemoteMode.mouse.next == .keyboard, "web remote mode cycles back to keyboard")
    }

    static func checkWebRuntimeShowsVirtualCursor() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let appState = try String(contentsOf: root.appending(path: "Sources/TVShellCore/App/AppState.swift"))
        try expect(appState.contains("webRemoteMode: WebRemoteMode = .mouse"), "browser defaults to virtual mouse mode")

        let webRuntime = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Runtime/WebAppRuntimeView.swift"))
        try expect(webRuntime.contains("tvShellSetMode"), "web runtime exposes a mode setter for showing the cursor immediately")
        try expect(webRuntime.contains("didFinish"), "web runtime reapplies virtual cursor after page navigation")
        try expect(webRuntime.contains("tv-shell-cursor-label"), "virtual cursor includes a visible TV label")
        try expect(webRuntime.contains("tv-shell-keyboard"), "web runtime injects an in-browser virtual keyboard")
        try expect(webRuntime.contains("zhuyinMap") && webRuntime.contains("ㄅ"), "web runtime injects a zhuyin browser keyboard")
        try expect(webRuntime.contains("candidateIndex"), "web zhuyin keyboard can focus candidates")
        try expect(webRuntime.contains("keyboardState.candidateIndex !== null"), "web zhuyin keyboard commits focused candidates")
        try expect(webRuntime.contains("mode === 'mouse'") && webRuntime.contains("ensureCursor()"), "mouse mode ensures the cursor exists")

        let keyboardView = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Input/VirtualKeyboardView.swift"))
        try expect(keyboardView.contains("state.focusedCandidateIndex == index"), "native zhuyin keyboard highlights focused candidates")
        try expect(keyboardView.contains("注音組字後按上進入候選列"), "native zhuyin keyboard explains candidate selection")
    }

    static func checkSettingsFocusIncludesVideoAndWebZoom() throws {
        try expect(SettingsFocus.scale.next == .wallpaper, "settings moves from scale to wallpaper")
        try expect(SettingsFocus.wallpaper.next == .webZoom, "settings moves from wallpaper to web zoom")
        try expect(SettingsFocus.webZoom.next == .danmakuSize, "settings moves from web zoom to danmaku size")
        try expect(SettingsFocus.danmakuSize.next == .danmakuSpeed, "settings moves from danmaku size to danmaku speed")
        try expect(SettingsFocus.danmakuSpeed.next == .danmakuOpacity, "settings moves from danmaku speed to danmaku opacity")
        try expect(SettingsFocus.danmakuOpacity.next == .danmakuDensity, "settings moves from danmaku opacity to danmaku density")
        try expect(SettingsFocus.danmakuDensity.next == .videoSource, "settings moves from danmaku density to video source")
        try expect(SettingsFocus.videoSource.next == .scale, "settings wraps to scale")
        try expect(DanmakuDisplaySettings(sizeScale: 1.0).adjusted(previous: false).sizeScale == 1.1, "danmaku size setting grows in readable steps")
        try expect(DanmakuDisplaySettings(speedScale: 1.0).adjustedSpeed(previous: false).speedScale == 1.1, "danmaku speed setting grows in readable steps")
        try expect(DanmakuDisplaySettings(opacity: 0.8).adjustedOpacity(previous: true).opacity == 0.7, "danmaku opacity setting changes in readable steps")
        try expect(DanmakuDisplaySettings(density: 5).adjustedDensity(previous: false).density == 6, "danmaku density setting changes visible line count")
    }

    static func checkAnimeSourceAndDanmakuProviders() async throws {
        let episode = AnimeEpisode(
            id: "ep-1",
            title: "第一話",
            number: 1,
            identity: AnimeEpisodeIdentity(providerID: "mock", subjectID: "bangumi-1", episodeID: "1")
        )
        let source = StaticAnimeSourceProvider(
            id: "mock",
            displayName: "示範動畫源",
            results: [
                AnimeSearchResult(id: "show-1", title: "測試動畫", subtitle: "TV", episodes: [episode])
            ],
            streams: [
                episode.id: [
                    AnimeStreamCandidate(url: URL(string: "https://example.com/video.m3u8")!, quality: "1080p", priority: 90)
                ]
            ]
        )

        let results = try await source.search(AnimeSearchQuery(keyword: "測試"))
        try expect(results.first?.title == "測試動畫", "anime source searches title")

        let streams = try await source.streams(for: episode)
        try expect(streams.first?.quality == "1080p", "anime source resolves stream candidates")

        let danmaku = StaticDanmakuProvider(comments: [
            DanmakuComment(time: 1.2, text: "開場", colorHex: "#FFFFFF", mode: .scroll)
        ])
        let comments = try await danmaku.comments(for: episode.identity)
        try expect(comments.first?.text == "開場", "danmaku provider returns timed comments")
    }

    static func checkAnimeRuntimeStateNavigation() throws {
        var state = AnimeRuntimeState(titleCount: 12, episodeCount: 8)
        state.apply(.right)
        try expect(state.focusedTitleIndex == 1, "anime right moves focused title on title grid")
        state.apply(.down, titleColumns: 6)
        try expect(state.focusedTitleIndex == 7, "anime down moves to the same column on the next poster row")
        state.apply(.up, titleColumns: 6)
        try expect(state.focusedTitleIndex == 1, "anime up moves to the previous poster row")
        state.apply(.select)
        try expect(state.phase == .details, "anime select opens title details")
        state.apply(.select)
        try expect(state.phase == .episodes, "anime detail select opens episode list")
        state.apply(.right)
        try expect(state.focusedEpisodeIndex == 1, "anime right moves focused episode in episode list")
        state.apply(.down)
        try expect(state.focusedEpisodeIndex == 5, "anime down moves to the same column on the next episode row")
        state.apply(.up)
        try expect(state.focusedEpisodeIndex == 1, "anime up moves to the same column on the previous episode row")
        state.apply(.left)
        try expect(state.focusedEpisodeIndex == 0, "anime left moves focused episode")
        state.apply(.select)
        try expect(state.phase == .playing, "anime select starts playback")
        state.apply(.menu)
        try expect(state.isDanmakuVisible == false, "anime menu toggles danmaku")
        state.apply(.back)
        try expect(state.phase == .episodes, "anime back returns to episode browser")
        state.apply(.back)
        try expect(state.phase == .details, "anime episode back returns to detail view")
        state.apply(.back)
        try expect(state.phase == .titles, "anime detail back returns to title grid")
    }

    static func checkExternalAnimeIntegrations() throws {
        let bangumiRequest = try BangumiAPI.searchSubjectsRequest(keyword: "芙莉蓮")
        try expect(bangumiRequest.url.absoluteString == "https://api.bgm.tv/v0/search/subjects?limit=30", "bangumi search endpoint requests more subject results")
        try expect(bangumiRequest.method == "POST", "bangumi search uses POST")
        let bangumiBody = String(data: bangumiRequest.body ?? Data(), encoding: .utf8) ?? ""
        try expect(bangumiBody.contains("\"keyword\":\"芙莉蓮\""), "bangumi search body contains keyword")
        try expect(bangumiBody.contains("\"type\":[2]"), "bangumi search filters anime subjects")

        let bangumiJSON = """
        {
          "data": [
            {
              "id": 424883,
              "name": "Sousou no Frieren",
              "name_cn": "葬送的芙莉蓮",
              "summary": "勇者一行打倒魔王之後。",
              "eps": 28,
              "images": {
                "large": "https://example.com/frieren.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let bangumiSubjects = try BangumiAPI.decodeSubjectSearch(bangumiJSON)
        try expect(bangumiSubjects.first?.title == "葬送的芙莉蓮", "bangumi decoder prefers Chinese title")
        try expect(bangumiSubjects.first?.episodeCount == 28, "bangumi decoder reads episode count")
        try expect(bangumiSubjects.first?.coverURL?.absoluteString == "https://example.com/frieren.jpg", "bangumi decoder reads cover image")

        let signature = DandanplaySignature.signature(
            appID: "app123",
            timestamp: 1_735_660_800,
            path: "/api/v2/comment/123450001",
            appSecret: "secret456"
        )
        try expect(signature == "oykjtAeMjRLO9sAerNa9hMyQZqFdBcWneI/ED4BerSQ=", "dandanplay signature matches documented algorithm")

        let commentsJSON = """
        {
          "comments": [
            { "p": "1.200,1,25,16777215,0", "m": "開場" },
            { "p": "3.500,5,25,16711680,0", "m": "頂部彈幕" }
          ]
        }
        """.data(using: .utf8)!
        let parsedComments = try DandanplayAPI.decodeComments(commentsJSON)
        try expect(parsedComments.first?.time == 1.2, "dandanplay parser reads timestamp")
        try expect(parsedComments[1].mode == .top, "dandanplay parser maps top mode")

        let combined = DanmakuAggregator.merge([
            [DanmakuComment(time: 2.0, text: "B"), DanmakuComment(time: 1.0, text: "A")],
            [DanmakuComment(time: 1.0, text: "A"), DanmakuComment(time: 3.0, text: "C")]
        ])
        try expect(combined.map(\.text) == ["A", "B", "C"], "danmaku aggregator sorts and deduplicates")

        let selected = AnimeStreamSelector.bestCandidate(from: [
            AnimeStreamCandidate(url: URL(string: "https://example.com/720.m3u8")!, quality: "720p", priority: 90),
            AnimeStreamCandidate(url: URL(string: "https://example.com/1080.m3u8")!, quality: "1080p", priority: 80)
        ])
        try expect(selected?.quality == "1080p", "stream selector balances priority and quality")
    }

    static func checkDandanplayConfiguredProvider() async throws {
        let emptyCredentials = DandanplayCredentials(appID: "", appSecret: "")
        try expect(emptyCredentials.isConfigured == false, "empty dandanplay credentials are not configured")

        let credentials = DandanplayCredentials(appID: "app123", appSecret: "secret456")
        try expect(credentials.isConfigured, "filled dandanplay credentials are configured")
        let environmentCredentials = DandanplayCredentials.environment([
            "TVSHELL_DANDANPLAY_APP_ID": "env-app",
            "TVSHELL_DANDANPLAY_APP_SECRET": "env-secret"
        ])
        try expect(environmentCredentials.appID == "env-app", "dandanplay app id loads from environment")
        try expect(environmentCredentials.appSecret == "env-secret", "dandanplay app secret loads from environment")

        let response = """
        {
          "comments": [
            { "p": "9.000,1,25,16777215,0", "m": "遠端彈幕" }
          ]
        }
        """.data(using: .utf8)!
        let transport = StaticAnimeHTTPTransport(routes: [
            "https://api.dandanplay.net/api/v2/comment/123450001?withRelated=true": response
        ])
        let provider = DandanplayDanmakuProvider(
            credentials: credentials,
            timestamp: 1_735_660_800,
            transport: transport
        )
        let comments = try await provider.comments(for: AnimeEpisodeIdentity(
            providerID: "bangumi",
            subjectID: "424883",
            episodeID: "123450001"
        ))

        try expect(comments.first?.text == "遠端彈幕", "configured provider fetches dandanplay comments")
        try expect(transport.requests.first?.headers["X-AppId"] == "app123", "configured provider sends dandanplay app id")
    }

    static func checkDandanplaySearchEpisodesFallback() async throws {
        let credentials = DandanplayCredentials(appID: "app123", appSecret: "secret456")
        let searchRequest = DandanplayAPI.searchEpisodesRequest(
            anime: "葬送的芙莉蓮",
            episode: 1,
            appID: credentials.appID,
            appSecret: credentials.appSecret,
            timestamp: 1_735_660_800
        )
        try expect(searchRequest.url.absoluteString.contains("https://api.dandanplay.net/api/v2/search/episodes"), "dandanplay searches episode ids")
        try expect(searchRequest.url.absoluteString.contains("anime="), "dandanplay search includes anime query")
        try expect(searchRequest.url.absoluteString.contains("episode=1"), "dandanplay search includes episode number")
        try expect(searchRequest.headers["X-AppId"] == "app123", "dandanplay search sends app id")

        let searchJSON = """
        {
          "animes": [
            {
              "animeId": 12345,
              "animeTitle": "葬送的芙莉蓮",
              "episodes": [
                { "episodeId": 123450001, "episodeTitle": "第 1 話", "episodeNumber": "1" }
              ]
            }
          ]
        }
        """.data(using: .utf8)!
        let matchedID = try DandanplayAPI.decodeEpisodeSearch(searchJSON, preferredEpisode: 1)
        try expect(matchedID == "123450001", "dandanplay search decoder extracts episode id")

        let commentsJSON = """
        {
          "comments": [
            { "p": "2.000,1,25,16777215,0", "m": "Dandanplay 彈幕" }
          ]
        }
        """.data(using: .utf8)!
        let commentRequest = DandanplayAPI.commentRequest(
            episodeID: "123450001",
            appID: credentials.appID,
            appSecret: credentials.appSecret,
            timestamp: 1_735_660_800
        )
        let transport = StaticAnimeHTTPTransport(routes: [
            searchRequest.url.absoluteString: searchJSON,
            commentRequest.url.absoluteString: commentsJSON
        ])
        let provider = DandanplayDanmakuProvider(
            credentials: credentials,
            timestamp: 1_735_660_800,
            transport: transport
        )
        let comments = try await provider.comments(for: AnimeEpisodeIdentity(
            providerID: "bangumi-youtube",
            subjectID: "葬送的芙莉蓮",
            episodeID: "1"
        ))
        try expect(comments.first?.text == "Dandanplay 彈幕", "dandanplay provider searches episode id before loading comments")
    }

    @MainActor
    static func checkYouTubeNativeRuntimeAndAPI() throws {
        let youtubeApp = SeedApps.defaultApps.first(where: { app in
            if case .youtube = app.target { return true }
            return false
        })
        guard let youtubeApp else {
            throw CheckFailure("missing native youtube app")
        }
        try expect(youtubeApp.name == "YouTube", "youtube app keeps branded name")

        let state = AppState(apps: SeedApps.defaultApps)
        state.focusedAppID = youtubeApp.id
        state.handle(.select)
        try expect(state.activeRuntime == .youtube(youtubeApp), "select opens native youtube runtime")

        let credentials = YouTubeCredentials.environment([
            "TVSHELL_YOUTUBE_API_KEY": "abc123"
        ])
        try expect(credentials.apiKey == "abc123", "youtube api key loads from environment")
        try expect(credentials.isConfigured, "youtube api key marks credentials configured")

        let request = try YouTubeDataAPI.searchRequest(
            query: "lofi",
            credentials: credentials,
            maxResults: 12
        )
        try expect(request.url.absoluteString.contains("https://www.googleapis.com/youtube/v3/search"), "youtube search uses official data api")
        try expect(request.url.absoluteString.contains("type=video"), "youtube search filters videos")
        try expect(request.url.absoluteString.contains("videoEmbeddable=true"), "youtube search asks for embeddable videos")
        try expect(request.url.absoluteString.contains("videoSyndicated=true"), "youtube search asks for externally playable videos")
        try expect(request.url.absoluteString.contains("maxResults=12"), "youtube search includes max results")
        try expect(request.url.absoluteString.contains("key=abc123"), "youtube search includes api key")

        let response = """
        {
          "items": [
            {
              "id": { "videoId": "abcXYZ" },
              "snippet": {
                "title": "測試影片",
                "channelTitle": "測試頻道",
                "description": "描述",
                "thumbnails": {
                  "high": { "url": "https://example.com/thumb.jpg" }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let videos = try YouTubeDataAPI.decodeSearchResponse(response)
        try expect(videos.first?.id == "abcXYZ", "youtube decoder reads video id")
        try expect(videos.first?.title == "測試影片", "youtube decoder reads title")

        var youtubeState = YouTubeRuntimeState(itemCount: 8)
        youtubeState.apply(.right)
        try expect(youtubeState.focusedIndex == 1, "youtube right moves focus")
        youtubeState.apply(.down)
        try expect(youtubeState.focusedIndex == 4, "youtube down moves focus to the next visual row")
        youtubeState.apply(.up)
        try expect(youtubeState.focusedIndex == 1, "youtube up moves focus to the previous visual row")
        youtubeState.apply(.select)
        try expect(youtubeState.phase == .playing, "youtube select starts playback")
        youtubeState.apply(.back)
        try expect(youtubeState.phase == .browsing, "youtube back returns to native list")
    }

    static func checkYouTubeEmbedPageIncludesOriginAndFallback() throws {
        let page = YouTubeEmbedPage(videoID: "abcXYZ", startSeconds: 65)
        try expect(page.origin.absoluteString == "https://mactv.local", "youtube embed uses stable origin")
        try expect(page.watchURL.absoluteString == "https://www.youtube.com/watch?v=abcXYZ", "youtube embed exposes watch fallback url")

        let html = page.html
        try expect(html.contains("origin=https%3A%2F%2Fmactv.local"), "youtube iframe includes encoded origin")
        try expect(html.contains(#"referrerpolicy="strict-origin-when-cross-origin""#), "youtube iframe sends strict origin referrer")
        try expect(html.contains("onError"), "youtube iframe handles player errors")
        try expect(html.contains("前往 YouTube 觀看影片"), "youtube iframe includes user-facing fallback link")
        try expect(html.contains("controls=0"), "youtube player hides youtube web controls behind MacTV controls")
        try expect(html.contains("cc_load_policy=1"), "youtube player requests captions by default")
        try expect(html.contains("cc_lang_pref=zh-Hant"), "youtube player prefers Traditional Chinese captions")
        try expect(html.contains("getDuration"), "youtube player exposes duration to custom shell")
        try expect(html.contains("tvShellYouTubeState"), "youtube player exposes state for custom shell")
        try expect(html.contains("start=65"), "youtube player can resume from a saved start second")
        try expect(html.contains("command === 'restart'"), "youtube player can restart from zero through the custom shell")
    }

    static func checkYouTubeLayoutAndPlayerShell() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let youtubeRuntime = try String(contentsOf: root.appending(path: "Sources/TVShellCore/YouTube/YouTubeRuntimeView.swift"))
        try expect(youtubeRuntime.contains("let cardWidth = 360 * metrics.scale"), "youtube cards use stable card width")
        try expect(youtubeRuntime.contains("let thumbnailHeight = 202 * metrics.scale"), "youtube cards use stable thumbnail height")
        try expect(youtubeRuntime.contains("MacTVYouTubeControls"), "youtube runtime renders custom player controls")
        try expect(youtubeRuntime.contains("startSeconds: controller.resumeTime(for: video)"), "youtube runtime resumes from saved history")
        try expect(youtubeRuntime.contains("recordPlaybackTime"), "youtube runtime records playback progress")
        try expect(youtubeRuntime.contains("restartOnSelect: controller.canRestartFromBeginningWithSelect"), "youtube OK restarts only from the initial playback HUD")

        let webRuntime = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Runtime/WebAppRuntimeView.swift"))
        try expect(webRuntime.contains("remoteScrollByCommand"), "browser runtime exposes remote scroll command")
        try expect(webRuntime.contains("command === 'fastForward'"), "browser can scroll down by remote command")
        try expect(webRuntime.contains("command === 'rewind'"), "browser can scroll up by remote command")
    }

    static func checkBangumiYouTubeAnimeSourceFindsPlayableCandidates() async throws {
        let bangumiResponse = """
        {
          "data": [
            {
              "id": 424883,
              "name": "Sousou no Frieren",
              "name_cn": "葬送的芙莉蓮",
              "summary": "勇者一行打倒魔王之後。",
              "eps": 2,
              "date": "2023-09-29",
              "rank": 1,
              "rating": { "score": 8.8, "total": 10000 }
            }
          ]
        }
        """.data(using: .utf8)!
        let youtubeResponse = """
        {
          "items": [
            {
              "id": { "videoId": "jjk01" },
              "snippet": {
                "title": "咒術迴戰 第 1 話",
                "channelTitle": "錯誤作品頻道",
                "description": "不同作品",
                "thumbnails": {
                  "high": { "url": "https://example.com/jjk.jpg" }
                }
              }
            },
            {
              "id": { "videoId": "frierenShort" },
              "snippet": {
                "title": "葬送的芙莉蓮 shorts 精華片段",
                "channelTitle": "剪輯頻道",
                "description": "短影音",
                "thumbnails": {
                  "high": { "url": "https://example.com/short.jpg" }
                }
              }
            },
            {
              "id": { "videoId": "frieren01" },
              "snippet": {
                "title": "葬送的芙莉蓮 第 1 話 日語中字",
                "channelTitle": "Muse木棉花-TW",
                "description": "合法上架片段",
                "thumbnails": {
                  "high": { "url": "https://example.com/frieren.jpg" }
                }
              }
            },
            {
              "id": { "videoId": "frierenBackup01" },
              "snippet": {
                "title": "葬送的芙莉蓮 第 1 話 中文字幕",
                "channelTitle": "備援頻道",
                "description": "正確作品與集數",
                "thumbnails": {
                  "high": { "url": "https://example.com/frieren-backup.jpg" }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let bangumiRequest = try BangumiAPI.searchSubjectsRequest(keyword: "芙莉蓮")
        let youtubeRequest = try YouTubeDataAPI.searchRequest(
            query: "葬送的芙莉蓮 Sousou no Frieren 第1話 EP1 日語 中文字幕 繁中 木棉花 Muse Ani-One 羚邦 動畫",
            credentials: YouTubeCredentials(apiKey: "yt-key"),
            maxResults: 10,
            profile: .animeEpisode
        )
        try expect(youtubeRequest.url.absoluteString.contains("videoDuration=long"), "anime youtube search excludes shorts with long duration filter")
        let transport = StaticAnimeHTTPTransport(routes: [
            bangumiRequest.url.absoluteString: bangumiResponse,
            youtubeRequest.url.absoluteString: youtubeResponse
        ])
        let provider = BangumiYouTubeAnimeSourceProvider(
            youtubeCredentials: YouTubeCredentials(apiKey: "yt-key"),
            transport: transport
        )

        let results = try await provider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(results.first?.title == "葬送的芙莉蓮", "bangumi youtube provider uses bangumi title")
        try expect(results.first?.airDate == "2023-09-29", "bangumi youtube provider carries air date")
        try expect(results.first?.score == 8.8, "bangumi youtube provider carries score")
        try expect(results.first?.rank == 1, "bangumi youtube provider carries rank")
        try expect(results.first?.episodes.count == 2, "bangumi youtube provider creates episode list")

        guard let episode = results.first?.episodes.first else {
            throw CheckFailure("missing bangumi youtube episode")
        }
        let streams = try await provider.streams(for: episode)
        try expect(streams.first?.url.absoluteString == "youtube://frieren01", "bangumi youtube provider ranks authorized youtube candidate first")
        try expect(streams.first?.quality == "YouTube", "bangumi youtube provider labels youtube source")
        try expect(streams.contains { $0.url.absoluteString == "youtube://frierenBackup01" }, "bangumi youtube provider keeps matching non-authorized videos as fallback")
        try expect(streams.contains { $0.url.absoluteString == "youtube://jjk01" } == false, "bangumi youtube provider filters videos from a different anime")

        let wrongOnlyYouTubeResponse = """
        {
          "items": [
            {
              "id": { "videoId": "jjk01" },
              "snippet": {
                "title": "咒術迴戰 第 1 話",
                "channelTitle": "錯誤作品頻道",
                "description": "不同作品",
                "thumbnails": {
                  "high": { "url": "https://example.com/jjk.jpg" }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let wrongOnlyProvider = BangumiYouTubeAnimeSourceProvider(
            youtubeCredentials: YouTubeCredentials(apiKey: "yt-key"),
            transport: StaticAnimeHTTPTransport(routes: [
                bangumiRequest.url.absoluteString: bangumiResponse,
                youtubeRequest.url.absoluteString: wrongOnlyYouTubeResponse
            ])
        )
        let wrongOnlyResults = try await wrongOnlyProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        guard let wrongOnlyEpisode = wrongOnlyResults.first?.episodes.first else {
            throw CheckFailure("missing wrong-only bangumi youtube episode")
        }
        let wrongOnlyStreams = try await wrongOnlyProvider.streams(for: wrongOnlyEpisode)
        try expect(wrongOnlyStreams.isEmpty, "bangumi youtube provider refuses to play a different anime when no matching episode exists")

        let aliasOnlyYouTubeResponse = """
        {
          "items": [
            {
              "id": { "videoId": "frierenEnglish01" },
              "snippet": {
                "title": "Frieren Episode 1",
                "channelTitle": "Muse Asia",
                "description": "別名標題",
                "thumbnails": {
                  "high": { "url": "https://example.com/frieren-english.jpg" }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let aliasOnlyProvider = BangumiYouTubeAnimeSourceProvider(
            youtubeCredentials: YouTubeCredentials(apiKey: "yt-key"),
            transport: StaticAnimeHTTPTransport(routes: [
                bangumiRequest.url.absoluteString: bangumiResponse,
                youtubeRequest.url.absoluteString: aliasOnlyYouTubeResponse
            ])
        )
        let aliasOnlyResults = try await aliasOnlyProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        guard let aliasOnlyEpisode = aliasOnlyResults.first?.episodes.first else {
            throw CheckFailure("missing alias-only bangumi youtube episode")
        }
        let aliasOnlyStreams = try await aliasOnlyProvider.streams(for: aliasOnlyEpisode)
        try expect(aliasOnlyStreams.first?.url.absoluteString == "youtube://frierenEnglish01", "bangumi youtube provider accepts official alias titles")
    }

    static func checkAnimeHomeProviderAggregatesDistinctTitles() async throws {
        let first = AnimeSearchResult(id: "frieren", title: "葬送的芙莉蓮", episodes: [])
        let duplicate = AnimeSearchResult(id: "frieren-s2", title: "葬送的芙莉蓮 第二季", episodes: [])
        let second = AnimeSearchResult(id: "toradora", title: "虎子", episodes: [])
        let third = AnimeSearchResult(id: "gakkou", title: "女子高中生的虛度日常", episodes: [])
        let provider = AnimeHomeSourceProvider(
            base: KeywordAnimeSourceProvider(
                id: "home-base",
                displayName: "Home Base",
                resultsByKeyword: [
                    "葬送的芙莉蓮": [first, duplicate],
                    "虎子": [second],
                    "女子高中生": [third]
                ],
                streams: [:],
                failingKeywords: ["暫時失敗"]
            ),
            homeKeywords: ["葬送的芙莉蓮", "暫時失敗", "虎子", "女子高中生"]
        )

        let home = try await provider.search(AnimeSearchQuery(keyword: ""))
        let homeTitles = home.map(\.title)
        try expect(homeTitles == ["葬送的芙莉蓮", "虎子", "女子高中生的虛度日常"], "anime home provider returns one distinct work per homepage keyword: \(homeTitles)")

        let search = try await provider.search(AnimeSearchQuery(keyword: "葬送的芙莉蓮"))
        try expect(search.map(\.title) == ["葬送的芙莉蓮", "葬送的芙莉蓮 第二季"], "anime home provider keeps full search results for explicit search")
    }

    static func checkBuiltInAnimekoStyleSources() async throws {
        let sources = AnimeSourceCatalog.defaultSources
        try expect(sources.contains { $0.id == "mikan" && $0.title == "Mikan Project" }, "catalog includes built-in Mikan source")
        try expect(sources.contains { $0.id == "dmhy" && $0.title == "動漫花園" }, "catalog includes built-in DMHY source")
        try expect(sources.contains { $0.id == "ani-subs-bt" && $0.title == "ani-subs BT 訂閱" }, "catalog includes ani-subs BT subscription source")
        try expect(sources.contains { $0.id == "jellyfin" && $0.title == "Jellyfin" }, "catalog includes Jellyfin source")
        try expect(sources.contains { $0.id == "emby" && $0.title == "Emby" }, "catalog includes Emby source")
        try expect(sources.first(where: { $0.id == "mikan" })?.defaultEnabled == false, "BT source is not enabled automatically")

        let rss = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
          <item>
            <title>[字幕組] 葬送的芙莉蓮 第01話 [1080p][繁中]</title>
            <link>magnet:?xt=urn:btih:ABCDEF123456</link>
            <enclosure url="https://mikan.example/frieren.torrent" />
          </item>
          <item>
            <title>[字幕組] 葬送的芙莉蓮 第02話 [1080p][繁中]</title>
            <link>magnet:?xt=urn:btih:ABCDEF123457</link>
          </item>
        </channel></rss>
        """.data(using: .utf8)!
        let btCoverRequest = try BangumiAPI.searchSubjectsRequest(keyword: "芙莉蓮")
        let btCoverResponse = """
        {
          "data": [
            {
              "id": 424883,
              "name": "Sousou no Frieren",
              "name_cn": "葬送的芙莉蓮",
              "images": {
                "large": "https://example.com/frieren-cover.jpg"
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let btProvider = BTFeedAnimeSourceProvider(
            id: "mikan",
            displayName: "Mikan Project",
            searchURLTemplate: "https://mikanani.me/RSS/Search?searchstr={keyword}",
            transport: StaticAnimeHTTPTransport(routes: [
                "https://mikanani.me/RSS/Search?searchstr=%E8%8A%99%E8%8E%89%E8%93%AE": rss,
                btCoverRequest.url.absoluteString: btCoverResponse
            ])
        )
        let btResults = try await btProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(btResults.count == 1, "BT RSS provider groups releases into one anime card")
        try expect(btResults.first?.title == "葬送的芙莉蓮", "Mikan RSS provider shows clean anime title")
        try expect(btResults.first?.episodeCount == 2, "BT RSS provider exposes grouped episode count")
        try expect(btResults.first?.episodes.map(\.number) == [1, 2], "BT RSS provider sorts grouped episodes")
        try expect(btResults.first?.episodes.first?.title == "第 1 話 · 1080p", "BT RSS provider shows clean episode labels")
        try expect(btResults.first?.coverURL?.absoluteString == "https://example.com/frieren-cover.jpg", "BT RSS provider enriches results with Bangumi covers")
        guard let btEpisode = btResults.first?.episodes.first else {
            throw CheckFailure("missing BT feed episode")
        }
        try expect(btEpisode.identity.episodeID == "1", "BT feed keeps episode id usable for danmaku lookup")
        try expect(btEpisode.identity.playbackURL?.scheme == "magnet", "BT feed stores magnet in playback url")
        let btStreams = try await btProvider.streams(for: btEpisode)
        try expect(btStreams.first?.url.scheme == "magnet", "BT feed provider prefers magnet streams")
        try expect(btStreams.first?.headers["resolver"] == "torrent", "BT feed stream marks torrent resolver")

        let seasonRSS = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
          <item>
            <title>[Jibaketa] 葬送的芙莉蓮 第二季 / Sousou no Frieren 2nd Season - 01-10 [1080p][繁中]</title>
            <link>magnet:?xt=urn:btih:SEASONPACK123456</link>
          </item>
        </channel></rss>
        """.data(using: .utf8)!
        let seasonProvider = BTFeedAnimeSourceProvider(
            id: "mikan",
            displayName: "Mikan Project",
            searchURLTemplate: "https://mikanani.me/RSS/Search?searchstr={keyword}",
            transport: StaticAnimeHTTPTransport(routes: [
                "https://mikanani.me/RSS/Search?searchstr=%E8%8A%99%E8%8E%89%E8%93%AE": seasonRSS,
                btCoverRequest.url.absoluteString: btCoverResponse
            ])
        )
        let seasonResults = try await seasonProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(seasonResults.first?.episodeCount == 10, "BT season pack expands into episode choices")
        try expect(seasonResults.first?.episodes.map(\.number) == Array(1...10), "BT season pack keeps episode numbers")
        try expect(seasonResults.first?.episodes.allSatisfy { $0.identity.playbackURL?.scheme == "magnet" } == true, "BT season pack episodes share pack playback url")

        let singleEpisodeRSS = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
          <item>
            <title>[Jibaketa] 不時輕聲地以俄語遮羞的鄰座艾莉同學 2nd Season - 10 END [1080p][繁中]</title>
            <link>magnet:?xt=urn:btih:ALYAEP10A</link>
          </item>
          <item>
            <title>[Jibaketa] 不時輕聲地以俄語遮羞的鄰座艾莉同學 2nd Season - 10 END [1080p][繁中][Mirror]</title>
            <link>magnet:?xt=urn:btih:ALYAEP10B</link>
          </item>
        </channel></rss>
        """.data(using: .utf8)!
        let alyaRequest = try BangumiAPI.searchSubjectsRequest(keyword: "艾莉")
        let alyaResponse = """
        { "data": [ { "id": 1, "name": "Alya", "name_cn": "不時輕聲地以俄語遮羞的鄰座艾莉同學" } ] }
        """.data(using: .utf8)!
        let singleEpisodeProvider = BTFeedAnimeSourceProvider(
            id: "mikan",
            displayName: "Mikan Project",
            searchURLTemplate: "https://mikanani.me/RSS/Search?searchstr={keyword}",
            transport: StaticAnimeHTTPTransport(routes: [
                "https://mikanani.me/RSS/Search?searchstr=%E8%89%BE%E8%8E%89": singleEpisodeRSS,
                alyaRequest.url.absoluteString: alyaResponse
            ])
        )
        let singleEpisodeResults = try await singleEpisodeProvider.search(AnimeSearchQuery(keyword: "艾莉"))
        try expect(singleEpisodeResults.first?.episodes.map(\.number) == [10], "BT single episode release is not expanded or duplicated")

        let mediaConfigs = MediaServerAnimeSourceConfig.environment([
            "TVSHELL_JELLYFIN_BASE_URL": "https://media.example",
            "TVSHELL_JELLYFIN_API_KEY": "jf-key",
            "TVSHELL_JELLYFIN_USER_ID": "user-1",
            "TVSHELL_EMBY_BASE_URL": "https://emby.example",
            "TVSHELL_EMBY_API_KEY": "emby-key"
        ])
        try expect(mediaConfigs.map(\.id) == ["jellyfin", "emby"], "media server configs load Jellyfin and Emby from environment")

        let mediaTransport = HandlerAnimeHTTPTransport { request in
            let path = request.url.path
            let query = request.url.query ?? ""
            if path == "/Items", query.contains("IncludeItemTypes=Series") {
                return """
                {
                  "Items": [
                    {
                      "Id": "series-1",
                      "Name": "葬送的芙莉蓮",
                      "Overview": "自有媒體庫",
                      "ProductionYear": 2023
                    }
                  ]
                }
                """.data(using: .utf8)!
            }
            if path == "/Shows/series-1/Episodes" {
                return """
                {
                  "Items": [
                    {
                      "Id": "episode-1",
                      "Name": "第 1 話",
                      "IndexNumber": 1
                    }
                  ]
                }
                """.data(using: .utf8)!
            }
            throw AnimeHTTPError.missingRoute(request.url.absoluteString)
        }
        let mediaProvider = MediaServerAnimeSourceProvider(config: mediaConfigs[0], transport: mediaTransport)
        let mediaResults = try await mediaProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(mediaResults.first?.coverURL?.absoluteString.contains("/Items/series-1/Images/Primary") == true, "media server provider exposes cover url")
        let mediaEpisodes = try await mediaProvider.episodes(for: mediaResults[0])
        try expect(mediaEpisodes.first?.title == "第 1 話", "media server provider loads episodes")
        let mediaStreams = try await mediaProvider.streams(for: mediaEpisodes[0])
        try expect(mediaStreams.first?.url.absoluteString.contains("/Videos/episode-1/stream.mp4") == true, "media server provider creates direct stream url")
        try expect(mediaStreams.first?.headers["X-Emby-Token"] == "jf-key", "media server stream carries auth header")
    }

    static func checkAniSubsBTSubscriptionProvider() async throws {
        let subscriptionURL = URL(string: "https://sub.example/bt1.json")!
        let subscription = """
        {
          "exportedMediaSourceDataList": {
            "mediaSources": [
              {
                "factoryId": "rss",
                "version": 1,
                "arguments": {
                  "name": "AnimeGarden",
                  "searchConfig": {
                    "searchUrl": "https://garden.example/feed.xml?keyword={keyword}"
                  }
                }
              },
              {
                "factoryId": "web-selector",
                "version": 2,
                "arguments": {
                  "name": "Web Source",
                  "searchConfig": {
                    "searchUrl": "https://web.example/search?wd={keyword}"
                  }
                }
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let rss = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
          <item>
            <title>[字幕組] 葬送的芙莉蓮 第01話 [1080p][繁中]</title>
            <link>magnet:?xt=urn:btih:ANISUBS0001</link>
          </item>
        </channel></rss>
        """.data(using: .utf8)!
        let transport = StaticAnimeHTTPTransport(routes: [
            subscriptionURL.absoluteString: subscription,
            "https://garden.example/feed.xml?keyword=%E8%8A%99%E8%8E%89%E8%93%AE": rss
        ])
        let provider = AniSubsBTSubscriptionProvider(subscriptionURL: subscriptionURL, transport: transport)
        let results = try await provider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(results.count == 1, "ani-subs bt provider searches rss subscriptions")
        try expect(results.first?.episodes.first?.identity.providerID == "ani-subs-bt", "ani-subs episodes route streams through the parent adapter")
        guard let episode = results.first?.episodes.first else {
            throw CheckFailure("missing ani-subs episode")
        }
        let streams = try await provider.streams(for: episode)
        try expect(streams.first?.url.scheme == "magnet", "ani-subs bt provider returns torrent streams")
        try expect(streams.first?.headers["resolver"] == "torrent", "ani-subs stream marks torrent resolver")
    }

    static func checkTorrentPlaybackEngine() throws {
        let stream = AnimeStreamCandidate(
            url: URL(string: "magnet:?xt=urn:btih:ABCDEF1234567890&dn=Frieren")!,
            quality: "BT 1080p",
            priority: 90,
            headers: ["resolver": "torrent"]
        )
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TVShellChecks-Torrent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let engine = Aria2TorrentPlaybackEngine(cacheRoot: tempRoot, executablePath: "/usr/bin/aria2c")
        let downloadDirectory = engine.downloadDirectory(for: stream)
        let arguments = engine.arguments(for: stream, downloadDirectory: downloadDirectory)
        try expect(arguments.contains("--bt-prioritize-piece=head=32M,tail=8M"), "torrent playback prioritizes the head and tail pieces")
        try expect(arguments.contains("--file-allocation=none"), "torrent playback avoids slow preallocation")
        try expect(arguments.last == stream.url.absoluteString, "torrent playback passes the source URL to aria2c")

        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let sample = downloadDirectory.appendingPathComponent("第01話.mp4")
        let secondSample = downloadDirectory.appendingPathComponent("第02話.mp4")
        FileManager.default.createFile(atPath: sample.path, contents: Data(repeating: 1, count: 2_048))
        FileManager.default.createFile(atPath: secondSample.path, contents: Data(repeating: 1, count: 4_096))
        try expect(engine.playableFiles(in: downloadDirectory).contains { $0.lastPathComponent == sample.lastPathComponent }, "torrent playback discovers playable media files")
        try expect(engine.downloadProgress(in: downloadDirectory).downloadedBytes == 6_144, "torrent playback reports downloaded bytes")
        try expect(engine.downloadProgress(in: downloadDirectory).statusText.contains("已下載"), "torrent playback exposes readable progress text")
        try expect(engine.preferredPlayableFile(in: downloadDirectory, episodeNumber: 1)?.lastPathComponent == sample.lastPathComponent, "torrent playback picks the focused episode file from season packs")
        try expect(engine.downloadProgress(in: downloadDirectory, episodeNumber: 1).largestPlayableFileName == sample.lastPathComponent, "torrent progress labels the focused episode instead of the largest file")
        try engine.rememberDownload(for: stream, title: "葬送的芙莉蓮", subtitle: "第 1 話")
        try expect(engine.cachedDownloads().first?.title == "葬送的芙莉蓮", "torrent playback lists cached downloads with manifest titles")
        try engine.deleteDownload(for: stream)
        try expect(FileManager.default.fileExists(atPath: downloadDirectory.path) == false, "torrent playback can delete cached BT downloads")

        let engineSource = try String(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true).appending(path: "Sources/TVShellCore/Anime/TorrentPlaybackEngine.swift"))
        try expect(engineSource.contains("terminationHandler"), "torrent playback engine records aria2 termination instead of waiting silently")
        try expect(engineSource.contains("lastErrorOutput"), "torrent playback engine exposes aria2 stderr when BT cannot start")
        try expect(engineSource.contains("protocol TorrentPlaybackEngine"), "torrent playback engine can be swapped for a future libtorrent backend")
    }

    static func checkAnimeEpisodeGridLayout() throws {
        try expect(AnimeEpisodeGridLayout.rows(itemCount: 10, columns: 4) == [
            [0, 1, 2, 3],
            [4, 5, 6, 7],
            [8, 9]
        ], "episode grid layout creates stable rows")
        try expect(AnimeEpisodeGridLayout.rows(itemCount: 3, columns: 0) == [[0], [1], [2]], "episode grid layout clamps invalid columns")
    }

    @MainActor
    static func checkAnimekoStyleSourceCatalog() throws {
        let sources = AnimeSourceCatalog.defaultSources
        try expect(sources.count >= 20, "anime source catalog includes animeko-style source list")
        try expect(sources.first?.id == "bangumi-youtube", "catalog starts with playable bangumi youtube source")
        try expect(sources.contains { $0.title == "girigiri 愛動漫" }, "catalog includes girigiri source")
        try expect(sources.contains { $0.title == "喵物次元" && $0.health == .needsCloudflare }, "catalog marks cloudflare source")
        try expect(sources.contains { $0.title == "新優酷" && $0.health == .needsCaptcha }, "catalog marks captcha source")
        try expect(sources.contains { $0.title == "櫻花動漫" && $0.health == .failed }, "catalog marks failed source")

        guard let hoibi = sources.first(where: { $0.title == "吼哔動漫" }) else {
            throw CheckFailure("missing hoibi source")
        }
        try expect(hoibi.lines.map(\.title) == ["吼哔2線", "吼哔1線", "吼哔4線"], "hoibi source keeps screenshot line order")

        var catalog = AnimeSourceCatalogState(definitions: sources)
        try expect(catalog.enabledInstances.contains { $0.definition.title == "hanime1[720p]" } == false, "adult source is not enabled by default")
        try expect(catalog.focusedID == catalog.instances.first?.id, "catalog focuses first source by default")

        catalog.selectLine(sourceID: hoibi.id, lineID: "hoibi-1")
        try expect(catalog.instance(id: hoibi.id)?.selectedLine?.title == "吼哔1線", "catalog can select a source line")

        catalog.toggleEnabled(sourceID: "bangumi-youtube")
        try expect(catalog.instance(id: "bangumi-youtube")?.isEnabled == false, "catalog can disable a playable source")

        let firstID = catalog.instances[0].id
        let secondID = catalog.instances[1].id
        catalog.moveSource(sourceID: secondID, offset: -1)
        try expect(catalog.instances[0].id == secondID && catalog.instances[1].id == firstID, "catalog can reorder sources")

        let state = AppState(apps: SeedApps.defaultApps)
        guard let sourceApp = state.apps.first(where: { app in
            if case let .web(url) = app.target { return url.host == "anime-sources" }
            return false
        }) else {
            throw CheckFailure("missing anime source manager app")
        }
        state.focusedAppID = sourceApp.id
        state.handle(.select)
        try expect(state.activeRuntime == .animeSourceManagement, "select opens anime source management")
        let focusedBefore = state.focusedAnimeSourceID
        state.handle(.down)
        try expect(state.focusedAnimeSourceID != focusedBefore, "remote down moves anime source focus")
    }

    static func checkAnimeSourceRegistryUsesCatalog() async throws {
        let episode = AnimeEpisode(
            id: "mock-episode-1",
            title: "測試動畫 第 1 話",
            number: 1,
            identity: AnimeEpisodeIdentity(providerID: "mock-source", subjectID: "mock-title", episodeID: "1")
        )
        let mock = StaticAnimeSourceProvider(
            id: "mock-source",
            displayName: "Mock Source",
            results: [
                AnimeSearchResult(id: "mock-title", title: "測試動畫", subtitle: "Mock", episodes: [episode])
            ],
            streams: [
                episode.id: [
                    AnimeStreamCandidate(url: URL(string: "https://example.com/mock.m3u8")!, quality: "1080p", priority: 100)
                ]
            ]
        )
        var catalog = AnimeSourceCatalogState(definitions: [
            AnimeSourceDefinition(
                id: "needs-captcha",
                title: "需要驗證",
                iconLabel: "驗",
                lines: [AnimeSourceLine(id: "needs-captcha-main", title: "主線")],
                health: .needsCaptcha
            ),
            AnimeSourceDefinition(
                id: "missing-adapter",
                title: "尚未接入",
                iconLabel: "空",
                lines: [AnimeSourceLine(id: "missing-main", title: "主線")]
            ),
            AnimeSourceDefinition(
                id: "mock-source",
                title: "Mock Source",
                iconLabel: "M",
                lines: [AnimeSourceLine(id: "mock-main", title: "主線")]
            )
        ])
        let registry = AnimeSourceRegistry(adapters: [mock])
        let provider = CatalogAnimeSourceProvider(catalog: catalog, registry: registry)
        let results = try await provider.search(AnimeSearchQuery(keyword: "測試"))
        try expect(results.first?.title == "測試動畫", "catalog provider skips unavailable sources and uses registered adapter")
        let streams = try await provider.streams(for: episode)
        try expect(streams.first?.quality == "1080p", "catalog provider resolves through episode provider id")
        try expect(provider.displayName.contains("Mock Source"), "catalog provider display name reports active source")

        catalog.toggleEnabled(sourceID: "mock-source")
        let disabledProvider = CatalogAnimeSourceProvider(catalog: catalog, registry: registry)
        do {
            _ = try await disabledProvider.search(AnimeSearchQuery(keyword: "測試"))
            throw CheckFailure("catalog provider should fail when no playable adapter is enabled")
        } catch let error as AnimeSourceCatalogError {
            try expect(error == .noPlayableAdapter, "catalog provider reports no playable adapter")
        }

        let factoryProvider = AnimeSourceProviderFactory.provider(
            catalog: AnimeSourceCatalogState(definitions: AnimeSourceCatalog.defaultSources),
            youtubeCredentials: YouTubeCredentials(apiKey: "yt-key")
        )
        try expect(factoryProvider.id == "catalog-home", "factory creates homepage aggregator over catalog-backed anime provider")
    }

    static func checkCatalogAnimeSourceProviderAggregatesResults() async throws {
        let first = KeywordAnimeSourceProvider(
            id: "first-source",
            displayName: "First Source",
            resultsByKeyword: [
                "動漫": [
                    AnimeSearchResult(id: "frieren-a", title: "葬送的芙莉蓮", coverURL: nil, episodeCount: 1, episodes: []),
                    AnimeSearchResult(id: "toradora", title: "虎子", episodeCount: 25, episodes: [])
                ]
            ]
        )
        let second = KeywordAnimeSourceProvider(
            id: "second-source",
            displayName: "Second Source",
            resultsByKeyword: [
                "動漫": [
                    AnimeSearchResult(
                        id: "frieren-b",
                        title: "葬送的芙莉蓮",
                        coverURL: URL(string: "https://example.com/frieren.jpg"),
                        episodeCount: 28,
                        episodes: []
                    ),
                    AnimeSearchResult(id: "gakkou", title: "女子高中生的虛度日常", episodeCount: 12, episodes: [])
                ]
            ]
        )
        let failing = KeywordAnimeSourceProvider(
            id: "failing-source",
            displayName: "Failing Source",
            resultsByKeyword: [:],
            failingKeywords: ["動漫"]
        )
        let catalog = AnimeSourceCatalogState(definitions: [
            AnimeSourceDefinition(id: "first-source", title: "First Source", iconLabel: "F", lines: []),
            AnimeSourceDefinition(id: "failing-source", title: "Failing Source", iconLabel: "X", lines: []),
            AnimeSourceDefinition(id: "second-source", title: "Second Source", iconLabel: "S", lines: [])
        ])
        let provider = CatalogAnimeSourceProvider(
            catalog: catalog,
            registry: AnimeSourceRegistry(adapters: [first, second, failing])
        )

        let results = try await provider.search(AnimeSearchQuery(keyword: "動漫"))
        try expect(results.map(\.title) == ["葬送的芙莉蓮", "虎子", "女子高中生的虛度日常"], "catalog provider aggregates multiple enabled source results")
        try expect(results.first?.coverURL != nil, "catalog provider keeps richer duplicate search result metadata")
    }

    static func checkSelectorAnimeSourceProvider() async throws {
        let config = SelectorAnimeSourceConfig(
            id: "selector-demo",
            displayName: "Selector Demo",
            searchURLTemplate: "https://source.example/search?q={keyword}",
            resultPattern: SelectorMatchPattern(
                pattern: #"<a class="anime" data-id="([^"]+)" href="([^"]+)">([^<]+)</a>"#,
                idGroup: 1,
                urlGroup: 2,
                titleGroup: 3
            ),
            episodePattern: SelectorMatchPattern(
                pattern: #"<a class="episode" data-number="([0-9]+)" href="([^"]+)">([^<]+)</a>"#,
                idGroup: 1,
                urlGroup: 2,
                titleGroup: 3
            ),
            streamPattern: SelectorStreamPattern(
                pattern: #"<source src="([^"]+)" data-quality="([^"]+)">"#,
                urlGroup: 1,
                qualityGroup: 2
            )
        )
        let searchHTML = #"<a class="anime" data-id="frieren" href="/anime/frieren">葬送的芙莉蓮</a>"#.data(using: .utf8)!
        let detailHTML = #"<a class="episode" data-number="1" href="/watch/frieren-1">第 1 話</a>"#.data(using: .utf8)!
        let watchHTML = #"<video><source src="https://cdn.example/frieren-1.m3u8" data-quality="1080p"></video>"#.data(using: .utf8)!
        let transport = StaticAnimeHTTPTransport(routes: [
            "https://source.example/search?q=%E8%8A%99%E8%8E%89%E8%93%AE": searchHTML,
            "https://source.example/anime/frieren": detailHTML,
            "https://source.example/watch/frieren-1": watchHTML
        ])
        let provider = SelectorAnimeSourceProvider(config: config, transport: transport)

        let results = try await provider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(results.first?.title == "葬送的芙莉蓮", "selector source parses search result title")
        try expect(results.first?.episodes.first?.title == "第 1 話", "selector source parses episode title from detail page")

        guard let episode = results.first?.episodes.first else {
            throw CheckFailure("missing selector episode")
        }
        let streams = try await provider.streams(for: episode)
        try expect(streams.first?.url.absoluteString == "https://cdn.example/frieren-1.m3u8", "selector source parses stream url")
        try expect(streams.first?.quality == "1080p", "selector source parses quality")

        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SelectorAnimeSourceConfig.self, from: encoded)
        try expect(decoded == config, "selector source config round trips through json")

        let blockedTransport = StaticAnimeHTTPTransport(routes: [
            "https://source.example/search?q=%E8%8A%99%E8%8E%89%E8%93%AE": "<title>Just a moment...</title><script>window._cf_chl_opt={}</script>".data(using: .utf8)!
        ])
        let blockedProvider = SelectorAnimeSourceProvider(config: config, transport: blockedTransport)
        do {
            _ = try await blockedProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
            throw CheckFailure("selector provider should report cloudflare captcha")
        } catch let error as SelectorAnimeSourceError {
            try expect(error == .captchaRequired(.cloudflare), "selector provider detects cloudflare challenge")
        }

        let envJSON = String(data: encoded, encoding: .utf8)!
        let envConfigs = try SelectorAnimeSourceConfig.environment([
            "TVSHELL_SELECTOR_SOURCES_JSON": "[\(envJSON)]"
        ])
        try expect(envConfigs.first == config, "selector configs load from environment json")

        let catalog = AnimeSourceCatalogState(definitions: [config.catalogDefinition])
        let factoryProvider = AnimeSourceProviderFactory.provider(
            catalog: catalog,
            youtubeCredentials: YouTubeCredentials(apiKey: ""),
            transport: transport,
            selectorConfigs: [config]
        )
        let factoryResults = try await factoryProvider.search(AnimeSearchQuery(keyword: "芙莉蓮"))
        try expect(factoryResults.first?.title == "葬送的芙莉蓮", "factory registers enabled selector source configs")
    }

    @MainActor
    static func checkAnimeSourcesExposePlayableStatusAndSearchChoices() throws {
        let sources = AnimeSourceCatalog.defaultSources
        try expect(sources.first(where: { $0.id == "bangumi-youtube" })?.health == .available, "bangumi youtube remains playable by default")
        try expect(sources.first(where: { $0.id == "girigiri" })?.health == .needsAdapter, "unimplemented scraped source is marked as needing adapter")
        try expect(sources.first(where: { $0.id == "hoibi" })?.defaultEnabled == false, "unimplemented scraped source is not enabled by default")
        try expect(sources.first(where: { $0.id == "miaowu" })?.health == .needsCloudflare, "cloudflare sources still show verification status")

        let keywords = AnimeSearchKeywordCatalog.defaultKeywords
        try expect(keywords.count >= 36, "anime runtime offers a broad homepage search range")
        try expect(keywords.contains("進擊的巨人"), "anime runtime includes mainstream search choices")
        try expect(keywords.contains("葬送的芙莉蓮"), "anime runtime uses full title rather than only short demo keyword")

        let state = AppState(apps: SeedApps.defaultApps)
        state.activeRuntime = .animeSourceManagement
        state.focusedAnimeSourceID = "girigiri"
        state.handle(.select)
        try expect(state.animeSourceCatalog.instance(id: "girigiri")?.isEnabled == false, "pending adapter source cannot be enabled from remote")
        try expect(state.statusMessage?.contains("待接入") == true, "pending adapter source explains why it cannot play")
    }

    static func checkBigScreenViewsStayScrollableAndWindowIsResizable() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let launcher = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Launcher/LauncherView.swift"))
        try expect(launcher.contains("ScrollView(.horizontal"), "launcher rows use horizontal scrolling instead of overflowing")
        try expect(launcher.contains("ScrollViewReader"), "launcher keeps focused app rows visible after watch history appears")
        try expect(launcher.contains("launcher-section-\\(section.id)"), "launcher sections expose stable scroll ids")
        try expect(launcher.contains(".scrollIndicators(.hidden)"), "launcher hides TV-unfriendly scroll indicators")
        try expect(launcher.contains("quickActionBar") == false, "launcher removes oversized quick action chips from the home screen")
        try expect(launcher.contains("34 * metrics.scale"), "launcher rows keep enough vertical padding for focus rings")

        for path in [
            "Sources/TVShellCore/Settings/SettingsView.swift",
            "Sources/TVShellCore/Settings/AppManagementView.swift",
            "Sources/TVShellCore/Settings/RemoteLearningView.swift"
        ] {
            let source = try String(contentsOf: root.appending(path: path))
            try expect(source.contains("GeometryReader"), "\(path) adapts to window size")
            try expect(source.contains("ScrollView"), "\(path) scrolls when the window is smaller than the content")
            try expect(source.contains("TVMetrics"), "\(path) uses TVMetrics scaling")
        }

        let settings = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Settings/SettingsView.swift"))
        try expect(settings.contains("ScrollViewReader"), "settings view keeps remote focus visible")
        try expect(settings.contains("scrollTo(focus"), "settings view scrolls to the focused setting")
        try expect(settings.contains("彈幕大小"), "settings view exposes danmaku size controls")
        try expect(settings.contains("彈幕速度"), "settings view exposes danmaku speed controls")
        try expect(settings.contains("彈幕透明度"), "settings view exposes danmaku opacity controls")
        try expect(settings.contains("彈幕密度"), "settings view exposes danmaku density controls")

        let appManagement = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Settings/AppManagementView.swift"))
        try expect(appManagement.contains("ScrollViewReader"), "app management keeps remote focus visible")
        try expect(appManagement.contains("scrollTo(id"), "app management scrolls to the focused app row")

        let app = try String(contentsOf: root.appending(path: "Sources/TVShell/TVShellApp.swift"))
        try expect(app.contains("minWidth: 960"), "root window can shrink below 1280 for smaller displays")
        try expect(app.contains("minHeight: 540"), "root window can shrink below 720 for smaller displays")
        try expect(app.contains(".windowStyle(.hiddenTitleBar)") == false, "root window keeps a visible macOS title bar for maximize")
        try expect(app.contains("@NSApplicationDelegateAdaptor(ShellAppDelegate.self)"), "root app installs the shell app delegate for reliable full screen entry")
        let shellWindow = try String(contentsOf: root.appending(path: "Sources/TVShellCore/App/ShellWindowManager.swift"))
        try expect(shellWindow.contains("enterKnownWindowFullScreen"), "shell window manager can explicitly enter the configured window into full screen")
        try expect(shellWindow.contains("configuredWindow"), "shell window manager remembers the SwiftUI window after configuration")

        let windowManager = try String(contentsOf: root.appending(path: "Sources/TVShellCore/App/ShellWindowManager.swift"))
        try expect(windowManager.contains(".resizable"), "window explicitly keeps resizable behavior")
        try expect(windowManager.contains("standardWindowButton(.zoomButton)"), "window explicitly enables the green zoom/maximize button")
        try expect(windowManager.contains("toggleFullScreen"), "window manager maximizes by entering macOS full screen")
        try expect(windowManager.contains("enterBorderlessTVFullScreen"), "window manager falls back to borderless TV full screen when macOS full screen is ignored")
        try expect(windowManager.contains("NSApp.presentationOptions"), "window manager hides Dock and menu bar in TV full screen fallback")
        try expect(windowManager.contains("screen.frame"), "window manager sizes fallback full screen to the physical display")
        try expect(windowManager.contains("requestInitialFullScreen"), "window enters macOS full screen automatically for TV mode")
        try expect(windowManager.contains("for delay in [") == false, "window manager avoids repeated full-screen toggles that can cancel the transition")
        try expect(windowManager.contains("applicationDidFinishLaunching"), "app delegate retries full screen after launch when a real window exists")

        let workflow = try String(contentsOf: root.appending(path: ".github/workflows/release.yml"))
        try expect(workflow.contains("MacTV.app"), "release workflow packages a real macOS app bundle")
        try expect(workflow.contains("CFBundlePackageType") && workflow.contains("APPL"), "release app bundle declares itself as a macOS app")
    }

    static func checkRuntimeNavigationAndPerformanceBudget() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        let youtubeRuntime = try String(contentsOf: root.appending(path: "Sources/TVShellCore/YouTube/YouTubeRuntimeView.swift"))
        try expect(youtubeRuntime.contains("updateGridColumns"), "youtube runtime updates remote navigation columns from current window size")
        try expect(youtubeRuntime.contains("ScrollViewReader"), "youtube runtime auto-scrolls focused cards into view")
        try expect(youtubeRuntime.contains("youtube-video-\\(index)"), "youtube video cards expose stable scroll ids")
        try expect(youtubeRuntime.contains("scrollTo(\"youtube-video-\\(index)\""), "youtube focus movement scrolls to focused card")
        try expect(youtubeRuntime.contains("videos = []"), "youtube runtime clears failed search results instead of showing demo items")

        let bangumiYouTube = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Anime/BangumiYouTubeAnimeSourceProvider.swift"))
        try expect(bangumiYouTube.contains("木棉花") && bangumiYouTube.contains("Muse"), "anime youtube source prioritizes licensed anime channels")

        let animeRuntime = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Anime/AnimeRuntimeView.swift"))
        try expect(animeRuntime.contains("isPlayerHUDVisible"), "anime player can hide the large playback HUD")
        try expect(animeRuntime.contains("hidePlayerHUDTask"), "anime player schedules HUD auto-hide")
        try expect(animeRuntime.contains("5_000_000_000"), "anime player hides HUD after five seconds")
        try expect(animeRuntime.contains("resumeTime(for:"), "anime player looks up resume time")
        try expect(animeRuntime.contains("recordPlaybackProgress"), "anime player records playback progress")
        try expect(animeRuntime.contains("restartOnSelect: canRestartFromBeginningWithSelect"), "anime player lets OK return to 00:00 only from the initial playback HUD")
        try expect(animeRuntime.contains("showPlayerHUD(allowRestart: true)"), "anime player enables restart only when playback first opens")
        try expect(animeRuntime.contains("currentYouTubeResumeTime"), "anime youtube playback receives saved resume time")
        try expect(animeRuntime.contains("deleteFocusedTorrentDownload"), "anime episode screen can delete BT downloads")
        try expect(animeRuntime.contains("torrentDownloadManager"), "anime runtime exposes a download manager overlay")
        try expect(animeRuntime.contains("focusedTorrentDownloadIndex"), "download manager is remote navigable")
        try expect(animeRuntime.contains("loadPlayer(stream, episode: episode)"), "anime torrent playback receives the selected episode")
        try expect(animeRuntime.contains("updateTitleColumns"), "anime runtime updates poster grid columns from current window size")
        try expect(animeRuntime.contains("updateEpisodeColumns"), "anime runtime updates episode navigation columns from current window size")
        try expect(animeRuntime.contains("anime-title-\\(index)"), "anime title cards expose stable scroll ids")
        try expect(animeRuntime.contains("anime-episode-\\(index)"), "anime episode cards expose stable scroll ids")
        try expect(animeRuntime.contains("scrollTo(\"anime-title-\\(index)\""), "anime title focus movement scrolls to focused poster")
        try expect(animeRuntime.contains("scrollTo(\"anime-episode-\\(index)\""), "anime episode focus movement scrolls to focused episode")
        try expect(animeRuntime.contains("fixedEpisodeCardWidth"), "anime episode grid uses fixed card width matched to remote navigation")
        try expect(animeRuntime.contains("ForEach(row, id: \\.self)"), "anime episode grid keys cards by stable visible offset")
        try expect(animeRuntime.contains("LazyVStack"), "anime episode grid uses manual rows instead of LazyVGrid diffing")
        try expect(animeRuntime.contains("lineLimit(2)") && animeRuntime.contains("animeHeader"), "anime headers constrain long BT titles")
        try expect(animeRuntime.contains("downloadProgress"), "anime player exposes torrent download progress")
        try expect(animeRuntime.contains("nativePlayableURL"), "anime player avoids handing unsupported files to AVPlayer")
        try expect(animeRuntime.contains("openExternalPlayer"), "anime player can fall back to an external player for unsupported anime containers")
        try expect(animeRuntime.contains("settings.density"), "danmaku overlay uses the configured density")
        try expect(animeRuntime.contains("settings.speedScale"), "danmaku overlay uses the configured speed")
        try expect(animeRuntime.contains("settings.opacity"), "danmaku overlay uses the configured opacity")
        try expect(animeRuntime.contains("searchKeywordBar") == false, "anime title browser does not show the old keyword chip row")
        try expect(animeRuntime.contains(".animation(TVMotion.focus, value: comments)") == false, "danmaku overlay does not animate every comment refresh")
        try expect(animeRuntime.contains("DanmakuOverlay(") && animeRuntime.contains("comments: controller.visibleDanmaku"), "anime player renders danmaku overlay")
        try expect(animeRuntime.contains("settings: appState.danmakuDisplaySettings"), "danmaku overlay receives user display settings")
        try expect(animeRuntime.contains("currentTime: controller.danmakuPlaybackTime"), "danmaku overlay receives playback time for movement")
        try expect(animeRuntime.contains("sampleDate: controller.danmakuPlaybackDate"), "danmaku overlay receives a sample date for smooth interpolation")
        try expect(animeRuntime.contains("TimelineView(.animation"), "danmaku overlay uses the animation timeline instead of step-only updates")
        try expect(animeRuntime.contains("interpolatedTime"), "danmaku overlay interpolates between player time samples")
        try expect(animeRuntime.contains("id: \\.element.stableIdentity"), "danmaku overlay keeps stable identities for moving comments")
        try expect(animeRuntime.contains("onPlaybackTime"), "youtube anime playback feeds time into danmaku")
        try expect(animeRuntime.contains("lifetime = 4.2 / settings.speedScale"), "danmaku overlay scroll speed follows the user setting")
        try expect(animeRuntime.contains(".zIndex(3)"), "danmaku overlay is above player surfaces")
        try expect(animeRuntime.contains("subtitleStatusText"), "anime player exposes subtitle status")
        try expect(animeRuntime.contains("loadMediaSelectionGroup(for: .legible)"), "anime player inspects subtitle tracks")
        try expect(animeRuntime.contains("isChineseSubtitleOption"), "anime player prefers Chinese subtitles")

        let liquidGlass = try String(contentsOf: root.appending(path: "Sources/TVShellCore/Design/LiquidGlass.swift"))
        try expect(liquidGlass.contains(".regularMaterial"), "liquid glass uses frosted glass material")
        try expect(liquidGlass.contains(".ultraThinMaterial") == false, "liquid glass avoids the previous ultra-thin material on every card")
        try expect(liquidGlass.contains("radius: isFocused ? 42") == false, "liquid glass avoids very large focus shadows")
        try expect(liquidGlass.contains(".clipShape(shape)"), "liquid glass clips material to rounded shape")
        try expect(liquidGlass.contains(".compositingGroup()"), "liquid glass composites rounded material without square corner artifacts")
    }

    static func checkGitHubReleaseWorkflow() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let workflowURL = root.appending(path: ".github/workflows/release.yml")
        let workflow = try String(contentsOf: workflowURL)
        try expect(workflow.contains("macos-15"), "release workflow builds on a Swift 6 capable macOS runner")
        try expect(workflow.contains("xcode-select"), "release workflow selects a compatible Xcode toolchain")
        try expect(workflow.contains("swift run TVShellChecks"), "release workflow runs TVShellChecks")
        try expect(workflow.contains("swift build -c release --product TVShell"), "release workflow builds release product")
        try expect(workflow.contains("Prepare Release Metadata"), "release workflow prepares metadata for automatic releases")
        try expect(workflow.contains("tag=latest"), "release workflow publishes a rolling latest release from successful main builds")
        try expect(workflow.contains("gh release delete \"$TAG\" --yes --cleanup-tag"), "release workflow refreshes the rolling latest release")
        try expect(workflow.contains("gh release create"), "release workflow publishes GitHub releases after successful builds")
        try expect(workflow.contains("github.event_name != 'pull_request'"), "release workflow skips publishing releases for pull requests")
        try expect(workflow.contains("upload-artifact"), "release workflow uploads build artifacts")
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
