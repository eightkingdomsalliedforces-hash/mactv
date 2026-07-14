package dev.tvshell.shared

import dev.tvshell.shared.anime.AnimePlayerCommand
import dev.tvshell.shared.anime.AnimePlayerState
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.BTRssParser
import dev.tvshell.shared.anime.BilibiliAnimeParser
import dev.tvshell.shared.anime.BangumiMetadataParser
import dev.tvshell.shared.anime.CSS1HtmlParser
import dev.tvshell.shared.anime.CSS1SubscriptionParser
import dev.tvshell.shared.anime.CSS1Anchor
import dev.tvshell.shared.anime.CSS1ContentClient
import dev.tvshell.shared.anime.CSS1Resolver
import dev.tvshell.shared.anime.DanmakuMotion
import dev.tvshell.shared.anime.DanmakuTimeline
import dev.tvshell.shared.anime.DandanplayParser
import dev.tvshell.shared.anime.DandanplayCredentials
import dev.tvshell.shared.anime.DandanplayService
import dev.tvshell.shared.anime.ServiceCredentialsParser
import dev.tvshell.shared.anime.SourceHealthState
import dev.tvshell.shared.anime.TorrentCacheEntry
import dev.tvshell.shared.anime.TorrentCachePolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class CrossPlatformAnimeTest {
    @Test
    fun bangumiMetadataKeepsChineseJapaneseAliasesAndEpisodeCount() {
        val subjects = BangumiMetadataParser.subjects(
            """{"data":[{"id":325285,"name":"Sousou no Frieren","name_cn":"葬送的芙莉蓮","eps":28,"summary":"勇者一行人的後日談","images":{"large":"https://lain.bgm.tv/pic/cover/l/test.jpg"}}]}""",
        )

        assertEquals(listOf("葬送的芙莉蓮", "Sousou no Frieren"), subjects.single().aliases)
        assertEquals(28, subjects.single().episodeCount)
        assertEquals("https://lain.bgm.tv/pic/cover/l/test.jpg", subjects.single().coverURL)

        val calendar = BangumiMetadataParser.calendar(
            """[{"weekday":{"id":1},"items":[{"id":456080,"name":"Test Anime","name_cn":"測試動畫","images":{"large":"http://lain.bgm.tv/test.jpg"}}]}]""",
        )
        assertEquals("測試動畫", calendar.single().title)
        assertEquals("https://lain.bgm.tv/test.jpg", calendar.single().coverURL)
    }

    @Test
    fun css1SubscriptionDecodesWebSelectorsInsteadOfTreatingJsonAsAnimeHtml() {
        val payload = """
            {"exportedMediaSourceDataList":{"mediaSources":[
              {"factoryId":"web-selector","arguments":{"name":"測試源","userAgent":"TVShell Test","searchConfig":{
                "searchUrl":"https://anime.example/search?wd={keyword}",
                "selectorSubjectFormatA":{"selectLists":".result a"},
                "selectorChannelFormatFlattened":{"selectEpisodeLists":".playlist","selectEpisodesFromList":"a","selectEpisodeLinksFromList":"","matchEpisodeSortFromName":"第\\\\s*(\\\\d+)\\\\s*集"},
                "matchVideo":{"enableNestedUrl":false,"matchVideoUrl":"(https?://[^\\\"]+\\\\.m3u8)","addHeadersToVideo":{"referer":"https://anime.example/"}}
              }}}
            ]}}
        """.trimIndent()

        val sources = CSS1SubscriptionParser.decode(payload)

        assertEquals(1, sources.size)
        assertEquals("測試源", sources.single().name)
        assertEquals(".result a", sources.single().searchSelector)
        assertEquals("https://anime.example/", sources.single().videoHeaders["Referer"])
    }

    @Test
    fun dandanplayKeepsAllRelatedCommentsAndMovesThemRightToLeft() {
        val comments = DandanplayParser.comments(
            """{"comments":[
              {"p":"1.200,1,25,16777215,0","m":"第一條"},
              {"p":"2.000,5,25,16711680,source-id","m":"第二條"}
            ]}""",
        )

        assertEquals(listOf("第一條", "第二條"), comments.map { it.text })
        assertEquals("#FF0000", comments[1].colorHex)
        assertTrue(DanmakuMotion.horizontalOffset(ageSeconds = 2.0, viewportWidth = 1920f, textWidth = 240f, speedScale = 1f) <
            DanmakuMotion.horizontalOffset(ageSeconds = 1.0, viewportWidth = 1920f, textWidth = 240f, speedScale = 1f))
        assertTrue(DanmakuMotion.lifetime(1920f, 240f, 1f) > 3.5)
    }

    @Test
    fun css1SearchIsDeferredUntilASelectedTitleNeedsEpisodes() = runBlocking {
        val subscription = """{"exportedMediaSourceDataList":{"mediaSources":[{"factoryId":"web-selector","arguments":{"name":"快源","searchConfig":{"searchUrl":"https://source.example/search?wd={keyword}","selectorSubjectFormatA":{"selectLists":".result a"},"selectorChannelFormatFlattened":{"selectEpisodeLists":".playlist","selectEpisodesFromList":"a"},"matchVideo":{"matchVideoUrl":"(https?://[^\\\"]+\\\\.m3u8)"}}}}]}}"""
        val client = object : CSS1ContentClient {
            val requested = mutableListOf<String>()
            override suspend fun get(url: String, headers: Map<String, String>): String {
                requested += url
                return when {
                    url.endsWith("css1.json") -> subscription
                    "/search?" in url -> "SEARCH"
                    url.endsWith("/show/frieren") -> "DETAIL"
                    url.endsWith("/play/1") -> "https://cdn.example/frieren-1080.m3u8"
                    else -> error("unexpected $url")
                }
            }
            override fun anchors(html: String, selector: String, baseURL: String): List<CSS1Anchor> = when (html) {
                "SEARCH" -> listOf(CSS1Anchor("葬送的芙莉蓮", "https://source.example/show/frieren"))
                "DETAIL" -> listOf(CSS1Anchor("第 1 集", "https://source.example/play/1"))
                else -> emptyList()
            }
            override fun blocks(html: String, selector: String): List<String> = if (html == "DETAIL") listOf(html) else emptyList()
            override fun encodeQuery(value: String): String = value
            override fun decodeURL(value: String): String = value
            override fun resolveURL(baseURL: String, value: String): String = value
        }
        val resolver = CSS1Resolver(client, "https://sub.example/css1.json")
        assertEquals(emptyList(), client.requested)

        val episodes = resolver.episodes("葬送的芙莉蓮")
        val streams = resolver.streams(episodes.single())

        assertEquals(listOf(1), episodes.map { it.number })
        assertEquals("https://cdn.example/frieren-1080.m3u8", streams.single().url)
        assertTrue(client.requested.first().endsWith("css1.json"))
    }

    @Test
    fun dandanplaySearchesEpisodeThenLoadsTheFullRelatedCommentSet() = runBlocking {
        val requests = mutableListOf<Pair<String, Map<String, String>>>()
        val client = object : CSS1ContentClient {
            override suspend fun get(url: String, headers: Map<String, String>): String {
                requests += url to headers
                return if ("search/episodes" in url) {
                    """{"animes":[{"episodes":[{"episodeId":123450001,"episodeNumber":"1"}]}]}"""
                } else {
                    """{"comments":[{"p":"1.0,1,25,16777215,0","m":"完整彈幕"}]}"""
                }
            }
            override fun anchors(html: String, selector: String, baseURL: String) = emptyList<CSS1Anchor>()
            override fun blocks(html: String, selector: String) = emptyList<String>()
            override fun encodeQuery(value: String) = value.replace(" ", "%20")
            override fun decodeURL(value: String) = value
            override fun resolveURL(baseURL: String, value: String) = value
        }
        val service = DandanplayService(client) { "signed:$it" }

        val comments = service.comments(
            title = "葬送的芙莉蓮",
            episode = 1,
            credentials = DandanplayCredentials("app-id", "app-secret"),
            timestamp = 123456,
        )

        assertEquals(listOf("完整彈幕"), comments.map { it.text })
        assertTrue(requests.first().first.contains("anime=葬送的芙莉蓮"))
        assertEquals("app-id", requests.first().second["X-AppId"])
        assertTrue(requests.last().first.endsWith("/123450001?withRelated=true"))
    }

    @Test
    fun sharedCredentialsFileKeepsDandanplayAndBilibiliLoginValues() {
        val credentials = ServiceCredentialsParser.decode(
            """{"dandanplay":{"appID":"dd-app","appSecret":"dd-secret"},"bilibili":{"cookie":"SESSDATA=session; bili_jct=csrf; DedeUserID=1"}}""",
        )

        assertEquals("dd-app", credentials.dandanplay.appID)
        assertEquals("dd-secret", credentials.dandanplay.appSecret)
        assertTrue(credentials.bilibiliCookie.contains("SESSDATA=session"))

        val netscape = ServiceCredentialsParser.decode(
            """# Netscape HTTP Cookie File
            #HttpOnly_.bilibili.com	TRUE	/	TRUE	2147483647	SESSDATA	session
            .bilibili.com	TRUE	/	FALSE	2147483647	bili_jct	csrf
            .bilibili.com	TRUE	/	FALSE	2147483647	DedeUserID	123""",
        )
        assertTrue(netscape.bilibiliCookie.contains("SESSDATA=session"))
        assertTrue(netscape.bilibiliCookie.contains("bili_jct=csrf"))

        val browserExport = ServiceCredentialsParser.decode(
            """{"bilibili":{"cookie":[{"domain":".bilibili.com","name":"SESSDATA","value":"session"},{"domain":"accounts.example.com","name":"private","value":"do-not-import"},{"domain":".bilibili.com","name":"bili_jct","value":"csrf"},{"domain":".bilibili.com","name":"DedeUserID","value":"123"}]}}""",
        )
        assertTrue(browserExport.bilibiliCookie.contains("DedeUserID=123"))
        assertFalse(browserExport.bilibiliCookie.contains("private="))
    }

    @Test
    fun danmakuTimelineRetainsACommentUntilItsWholeTextLeavesTheLeftEdge() {
        val comments = listOf(dev.tvshell.shared.anime.DanmakuComment(1.0, "測試彈幕"))

        assertEquals(1, DanmakuTimeline.active(comments, 2.0, 1920f, 240f, 1f).size)
        assertEquals(0, DanmakuTimeline.active(comments, 6.0, 1920f, 240f, 1f).size)
    }

    @Test
    fun animeSourceCatalogMatchesTheNativeMacTabs() {
        assertEquals(
            listOf(AnimeSourceKind.Bilibili, AnimeSourceKind.BangumiYouTube, AnimeSourceKind.YouTube),
            animeSourcesFor(AnimeTopTab.Recommended).map(AnimeSourceDefinition::kind),
        )
        assertEquals(
            listOf(AnimeSourceKind.AniGamer, AnimeSourceKind.YouTube),
            animeSourcesFor(AnimeTopTab.OfficialSources).map(AnimeSourceDefinition::kind),
        )
        assertEquals(
            listOf(AnimeSourceKind.CSS1, AnimeSourceKind.AniSubsBT, AnimeSourceKind.Mikan, AnimeSourceKind.DMHY),
            animeSourcesFor(AnimeTopTab.Subscriptions).map(AnimeSourceDefinition::kind),
        )
    }

    @Test
    fun changingAnimeTabsResetsContentAndUsesThatTabsSourceCount() {
        var state = CrossPlatformAnimeBrowserState().loaded(cardCount = 8)
        state = state.copy(isTopNavigationFocused = true).reduce(RemoteCommand.Right)
        assertEquals(AnimeTopTab.OfficialSources, state.focusedTopTab)
        assertEquals(CrossPlatformAnimePhase.Sources, state.phase)
        assertEquals(2, state.sourceCount)
        assertEquals(0, state.focusedSource)

        state = state.reduce(RemoteCommand.Right)
        assertEquals(AnimeTopTab.Subscriptions, state.focusedTopTab)
        assertEquals(4, state.sourceCount)
    }

    @Test
    fun standaloneAnimeHomeStartsWithTheRecommendedFeed() {
        val state = CrossPlatformAnimeBrowserState().loadingFirstSource()
        assertEquals(AnimeTopTab.Recommended, state.focusedTopTab)
        assertEquals(CrossPlatformAnimePhase.Loading, state.phase)
        assertEquals("load:0", state.pendingAction)
    }

    @Test
    fun animeTopNavigationMatchesTheFiveMacTabs() {
        var state = CrossPlatformAnimeBrowserState(sourceCount = 2)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Right).reduce(RemoteCommand.Right).reduce(RemoteCommand.Right)
        assertEquals(AnimeTopTab.Search, state.focusedTopTab)
        state = state.reduce(RemoteCommand.Down)
        assertFalse(state.isTopNavigationFocused)
        state = state.reduce(RemoteCommand.Up)
        assertTrue(state.isTopNavigationFocused)
    }

    @Test
    fun animeBrowserOpensARealFeedAndSelectsPlayback() {
        var state = CrossPlatformAnimeBrowserState(sourceCount = 2)
        state = state.reduce(RemoteCommand.Down).reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Loading, state.phase)
        state = state.loaded(cardCount = 3)
        assertEquals(CrossPlatformAnimePhase.Titles, state.phase)
        state = state.reduce(RemoteCommand.Down).reduce(RemoteCommand.Right).reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Details, state.phase)
        assertEquals(1, state.selectedCardIndex)
    }

    @Test
    fun animeLoadingCanBeCancelledWithBack() {
        var state = CrossPlatformAnimeBrowserState(sourceCount = 2, isTopNavigationFocused = false)
        state = state.reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Loading, state.phase)
        state = state.reduce(RemoteCommand.Back)
        assertEquals(CrossPlatformAnimePhase.Sources, state.phase)
        val root = CrossPlatformAnimeBrowserState(sourceCount = 2).reduce(RemoteCommand.Back)
        assertEquals("exit", root.pendingAction)
    }

    @Test
    fun animeTitleGridMovesLikeTheMacBrowser() {
        var state = CrossPlatformAnimeBrowserState(sourceCount = 2, gridColumns = 4).loaded(cardCount = 9)
            .copy(isTopNavigationFocused = false)
        state = state.reduce(RemoteCommand.Down)
        assertEquals(4, state.focusedCard)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Up)
        assertEquals(1, state.focusedCard)
        state = state.reduce(RemoteCommand.Up)
        assertTrue(state.isTopNavigationFocused)
    }
    @Test
    fun css1FiltersMetadataAndRanksPlayableQuality() {
        val episodes = CSS1HtmlParser.episodes(
            """
            <a href='/watch/1'>第 1 集</a>
            <a href='/rating'>豆瓣評分 8.1</a>
            <a href='/year'>2021</a>
            <a href='/watch/2'>第 2 話</a>
            """.trimIndent(),
            "https://source.example/show/86",
        )
        assertEquals(listOf(1, 2), episodes.map { it.number })

        val streams = CSS1HtmlParser.streams(
            """
            <source src='https://cdn.example/video-720p.mp4' label='720p'>
            <source src='https://cdn.example/video-1080p.mp4' label='1080p'>
            """.trimIndent(),
        )
        assertEquals("1080p", streams.first().quality)
        assertEquals(2, streams.size)
    }

    @Test
    fun btRssNormalizesMagnetAndSourceHealthSkipsFailedHost() {
        val items = BTRssParser.items(
            """
            <rss><channel><item><title>[Lilith-Raws] 葬送的芙莉蓮 - 01 [1080p]</title>
            <enclosure url='magnet:?xt=urn:btih:ABC123&amp;dn=Frieren' type='application/x-bittorrent'/>
            </item></channel></rss>
            """.trimIndent(),
        )
        assertEquals(1, items.first().episode)
        assertTrue(items.first().magnet.startsWith("magnet:?xt=urn:btih:ABC123"))

        var health = SourceHealthState()
        health = health.recordFailure("broken.example", "timeout")
        assertFalse(health.shouldLoad("broken.example"))
        health = health.reset("broken.example")
        assertTrue(health.shouldLoad("broken.example"))
    }

    @Test
    fun cacheCleanupAndPlayerCommandsArePortable() {
        val entries = listOf(
            TorrentCacheEntry("old", bytes = 700, lastAccessEpochSeconds = 10),
            TorrentCacheEntry("new", bytes = 600, lastAccessEpochSeconds = 100),
        )
        assertEquals(listOf("old"), TorrentCachePolicy.idsToDelete(entries, maxBytes = 900, nowEpochSeconds = 120, expirationSeconds = 1_000))

        var player = AnimePlayerState()
        player = player.reduce(AnimePlayerCommand.PlayPause)
        player = player.reduce(AnimePlayerCommand.FastForward)
        assertTrue(player.isPlaying)
        assertEquals(15, player.pendingSeekSeconds)
    }

    @Test
    fun animeEpisodeKeepsMasterStreamAndQualityAlternatives() {
        val master = AnimeStreamCandidate("https://cdn.example/master.m3u8", "自動")
        val variants = listOf(
            AnimeStreamCandidate("https://cdn.example/1080.m3u8", "1080p"),
            AnimeStreamCandidate("https://cdn.example/720.m3u8", "720p"),
        )
        var player = AnimePlayerState().loaded(master, variants)
        assertEquals(master.url, player.selectedCandidate?.url)
        assertEquals(3, player.candidates.size)
        player = player.reduce(AnimePlayerCommand.OpenSourcePicker)
            .reduce(AnimePlayerCommand.NextSource)
            .reduce(AnimePlayerCommand.ConfirmSource)
        assertEquals("1080p", player.selectedCandidate?.quality)
        assertEquals("load:https://cdn.example/1080.m3u8", player.pendingAction)
    }

    @Test
    fun animeJourneyMatchesMacDetailsEpisodesAndPlaybackOrder() {
        var state = CrossPlatformAnimeBrowserState(gridColumns = 4).loaded(cardCount = 8)
            .copy(isTopNavigationFocused = false, focusedCard = 2)

        state = state.reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Details, state.phase)
        assertEquals(2, state.selectedCardIndex)

        state = state.reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.EpisodeLoading, state.phase)
        assertEquals("episodes:2", state.pendingAction)

        state = state.episodesLoaded(episodeCount = 12)
        assertEquals(CrossPlatformAnimePhase.Episodes, state.phase)
        assertEquals(0, state.focusedEpisode)

        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Resolving, state.phase)
        assertEquals("streams:1", state.pendingAction)
    }

    @Test
    fun multipleAnimePlaybackLinesRequireTheSameExplicitPickerAsMac() {
        val candidates = listOf(
            AnimeStreamCandidate("https://cdn.example/master.m3u8", "自動"),
            AnimeStreamCandidate("https://cdn.example/1080.m3u8", "1080p"),
        )
        var state = CrossPlatformAnimeBrowserState().loaded(1)
            .copy(isTopNavigationFocused = false)
            .reduce(RemoteCommand.Select)
            .reduce(RemoteCommand.Select)
            .episodesLoaded(1)
            .reduce(RemoteCommand.Select)
            .streamsLoaded(candidates)

        assertEquals(CrossPlatformAnimePhase.Resolving, state.phase)
        assertTrue(state.isStreamPickerVisible)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Select)
        assertEquals(CrossPlatformAnimePhase.Playing, state.phase)
        assertEquals(1, state.selectedStreamIndex)
        assertEquals("load:https://cdn.example/1080.m3u8", state.pendingAction)
    }

    @Test
    fun animePlayerRemoteCommandsMatchMacHudSeekVolumeAndBack() {
        val candidate = AnimeStreamCandidate("https://cdn.example/1080.m3u8", "1080p")
        var state = CrossPlatformAnimeBrowserState().loaded(1)
            .copy(isTopNavigationFocused = false)
            .reduce(RemoteCommand.Select)
            .reduce(RemoteCommand.Select)
            .episodesLoaded(1)
            .reduce(RemoteCommand.Select)
            .streamsLoaded(listOf(candidate))
            .clearAction()

        state = state.reduce(RemoteCommand.Right)
        assertEquals(15, state.pendingSeekSeconds)
        assertEquals("seek:15", state.pendingAction)
        state = state.clearAction().reduce(RemoteCommand.Up)
        assertEquals("volume:up", state.pendingAction)
        state = state.clearAction().reduce(RemoteCommand.PlayPause)
        assertFalse(state.isPlaying)
        assertEquals("pause", state.pendingAction)
        state = state.clearAction().reduce(RemoteCommand.Back)
        assertEquals(CrossPlatformAnimePhase.Episodes, state.phase)
        assertEquals("stop", state.pendingAction)
    }

    @Test
    fun bilibiliSeasonAndPlaybackResponsesBecomeEpisodesAndCombinedStreams() {
        val episodes = BilibiliAnimeParser.episodes(
            """{"result":{"main_section":{"episodes":[{"id":123,"title":"1","long_title":"相遇","cid":456,"bvid":"BV1ABC"},{"id":124,"title":"2","long_title":"出發","cid":457,"bvid":"BV2ABC"}]}}}""",
        )
        assertEquals(listOf("第 1 集 · 相遇", "第 2 集 · 出發"), episodes.map { it.title })
        assertEquals("bilibili:123:456", episodes.first().id)

        val streams = BilibiliAnimeParser.streams(
            """{"result":{"quality":80,"accept_quality":[80,64],"durl":[{"url":"https://cdn.example/video.flv"}]}}""",
        )
        assertEquals(1, streams.size)
        assertEquals("1080p", streams.single().quality)
        assertEquals("https://www.bilibili.com/", streams.single().headers["Referer"])

        val danmaku = BilibiliAnimeParser.danmaku(
            """<i><d p="1.5,1,25,16777215,0,0,0,0">第一條&amp;彈幕</d><d p="3.0,5,25,16711680,0,0,0,0">置頂</d></i>""",
        )
        assertEquals(listOf("第一條&彈幕", "置頂"), danmaku.map { it.text })
        assertEquals("#FF0000", danmaku[1].colorHex)
    }

    @Test
    fun bilibiliEpisodesRemainUsableWhenTheRealApiOmitsBvid() {
        val episodes = BilibiliAnimeParser.episodes(
            """{"result":{"main_section":{"episodes":[{"aid":1806595774,"cid":39787692307,"id":4353829,"long_title":"先行片 PILOT（中文配音）","share_url":"https://www.bilibili.com/bangumi/play/ep4353829","title":"1","vid":""}]}}}""",
        )
        assertEquals(1, episodes.size)
        assertEquals("bilibili:4353829:39787692307", episodes.single().id)
    }

    @Test
    fun bilibiliPlaybackFailureKeepsTheRealRegionReason() {
        assertEquals(
            "抱歉您所在地区不可观看！",
            BilibiliAnimeParser.failureReason("""{"code":-10403,"message":"抱歉您所在地区不可观看！"}"""),
        )
    }
}
