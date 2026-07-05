import CoreGraphics
import Foundation
import TVShellCore

@main
struct TVShellChecks {
    static func main() async throws {
        try checkKeyCodeMapper()
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
        try checkWallpaperPresetCyclingAndProvider()
        try checkQuickActionsAndBrowserArePresent()
        try checkWebRemoteModeCycles()
        try checkSettingsFocusIncludesVideoAndWebZoom()
        try await checkAnimeSourceAndDanmakuProviders()
        try checkAnimeRuntimeStateNavigation()
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

    static func checkWallpaperPresetCyclingAndProvider() throws {
        try expect(WallpaperPreset.aurora.next == .ocean, "wallpaper cycles forward")
        try expect(WallpaperPreset.ocean.previous == .aurora, "wallpaper cycles backward")

        let provider = StaticWallpaperProvider(presets: [.aurora, .ocean])
        try expect(provider.featured().preset == .aurora, "static provider returns first featured wallpaper")
        try expect(provider.next(after: .aurora).preset == .ocean, "static provider returns next wallpaper")
    }

    static func checkQuickActionsAndBrowserArePresent() throws {
        let quickActions = LauncherLayout.quickActions(for: SeedApps.defaultApps)
        let quickHosts = quickActions.compactMap { app -> String? in
            if case let .web(url) = app.target { return url.host }
            return nil
        }
        try expect(quickHosts.contains("settings"), "settings is always available as a quick action")
        try expect(quickHosts.contains("remote-learning"), "remote setup is always available as a quick action")
        try expect(quickHosts.contains("app-management"), "app management is always available as a quick action")

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

    static func checkSettingsFocusIncludesVideoAndWebZoom() throws {
        try expect(SettingsFocus.scale.next == .wallpaper, "settings moves from scale to wallpaper")
        try expect(SettingsFocus.wallpaper.next == .webZoom, "settings moves from wallpaper to web zoom")
        try expect(SettingsFocus.webZoom.next == .videoSource, "settings moves from web zoom to video source")
        try expect(SettingsFocus.videoSource.next == .scale, "settings wraps to scale")
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
        var state = AnimeRuntimeState(episodeCount: 3)
        state.apply(.right)
        try expect(state.focusedEpisodeIndex == 1, "anime right moves focused episode")
        state.apply(.left)
        try expect(state.focusedEpisodeIndex == 0, "anime left moves focused episode")
        state.apply(.select)
        try expect(state.phase == .playing, "anime select starts playback")
        state.apply(.menu)
        try expect(state.isDanmakuVisible == false, "anime menu toggles danmaku")
        state.apply(.back)
        try expect(state.phase == .browsing, "anime back returns to episode browser")
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
