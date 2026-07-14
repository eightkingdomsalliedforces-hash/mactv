package dev.tvshell.shared

import dev.tvshell.shared.anime.AnimePlayerCommand
import dev.tvshell.shared.anime.AnimePlayerState
import dev.tvshell.shared.anime.BTRssParser
import dev.tvshell.shared.anime.CSS1HtmlParser
import dev.tvshell.shared.anime.SourceHealthState
import dev.tvshell.shared.anime.TorrentCacheEntry
import dev.tvshell.shared.anime.TorrentCachePolicy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CrossPlatformAnimeTest {
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
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Select)
        assertEquals("play:1", state.pendingAction)
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
}
