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
        try checkExternalAnimeIntegrations()
        try await checkDandanplayConfiguredProvider()
        try checkYouTubeNativeRuntimeAndAPI()
        try await checkBangumiYouTubeAnimeSourceFindsPlayableCandidates()
        try checkAnimekoStyleSourceCatalog()
        try await checkAnimeSourceRegistryUsesCatalog()
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

    static func checkExternalAnimeIntegrations() throws {
        let bangumiRequest = try BangumiAPI.searchSubjectsRequest(keyword: "芙莉蓮")
        try expect(bangumiRequest.url.absoluteString == "https://api.bgm.tv/v0/search/subjects", "bangumi search endpoint uses v0 subjects search")
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
              "eps": 28
            }
          ]
        }
        """.data(using: .utf8)!
        let bangumiSubjects = try BangumiAPI.decodeSubjectSearch(bangumiJSON)
        try expect(bangumiSubjects.first?.title == "葬送的芙莉蓮", "bangumi decoder prefers Chinese title")
        try expect(bangumiSubjects.first?.episodeCount == 28, "bangumi decoder reads episode count")

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

        var youtubeState = YouTubeRuntimeState(itemCount: 2)
        youtubeState.apply(.right)
        try expect(youtubeState.focusedIndex == 1, "youtube right moves focus")
        youtubeState.apply(.select)
        try expect(youtubeState.phase == .playing, "youtube select starts playback")
        youtubeState.apply(.back)
        try expect(youtubeState.phase == .browsing, "youtube back returns to native list")
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
              "eps": 2
            }
          ]
        }
        """.data(using: .utf8)!
        let youtubeResponse = """
        {
          "items": [
            {
              "id": { "videoId": "frieren01" },
              "snippet": {
                "title": "葬送的芙莉蓮 第 1 話",
                "channelTitle": "動畫頻道",
                "description": "合法上架片段",
                "thumbnails": {
                  "high": { "url": "https://example.com/frieren.jpg" }
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let bangumiRequest = try BangumiAPI.searchSubjectsRequest(keyword: "芙莉蓮")
        let youtubeRequest = try YouTubeDataAPI.searchRequest(
            query: "葬送的芙莉蓮 第 1 話",
            credentials: YouTubeCredentials(apiKey: "yt-key"),
            maxResults: 10
        )
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
        try expect(results.first?.episodes.count == 2, "bangumi youtube provider creates episode list")

        guard let episode = results.first?.episodes.first else {
            throw CheckFailure("missing bangumi youtube episode")
        }
        let streams = try await provider.streams(for: episode)
        try expect(streams.first?.url.absoluteString == "youtube://frieren01", "bangumi youtube provider resolves youtube candidate")
        try expect(streams.first?.quality == "YouTube", "bangumi youtube provider labels youtube source")
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

        catalog.toggleEnabled(sourceID: hoibi.id)
        try expect(catalog.instance(id: hoibi.id)?.isEnabled == false, "catalog can disable a source")

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
        try expect(factoryProvider.id == "catalog", "factory creates catalog-backed anime provider")
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
