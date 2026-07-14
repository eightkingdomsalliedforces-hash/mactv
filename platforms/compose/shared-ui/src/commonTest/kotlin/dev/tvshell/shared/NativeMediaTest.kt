package dev.tvshell.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeMediaTest {
    @Test
    fun watchHistoryKeepsRecentUniquePlayableCards() {
        val first = NativeMediaCard("first", "第一部", "頻道", "", "https://example.com/first")
        val second = NativeMediaCard("second", "第二部", "頻道", "", "https://example.com/second")
        val history = WatchHistoryState().record(first).record(second).record(first)
        assertEquals(listOf("first", "second"), history.entries.map { it.id })
    }

    @Test
    fun mediaPlayerStaysInsideTvshellAndRespondsToRemoteCommands() {
        var state = NativeMediaState(cardCount = 3)
        state = state.reduce(RemoteCommand.Down).reduce(RemoteCommand.Select)
        assertEquals(NativeMediaPhase.Player, state.phase)
        assertEquals("play:0", state.pendingAction)
        state = state.clearAction().reduce(RemoteCommand.PlayPause).reduce(RemoteCommand.FastForward)
        assertEquals(false, state.isPlaying)
        assertEquals(15, state.pendingSeekSeconds)
        assertEquals(NativeMediaPhase.Browser, state.reduce(RemoteCommand.Back).phase)
    }

    @Test
    fun bilibiliPopularResponseBecomesRemoteFriendlyCards() {
        val json = """{"data":{"list":[{"aid":42,"title":"葬送的芙莉蓮","pic":"//i0.hdslb.com/a.jpg","owner":{"name":"UP主"},"bvid":"BV123"}]}}"""
        val cards = NativeMediaParser.bilibili(json)
        assertEquals("葬送的芙莉蓮", cards.single().title)
        assertEquals("https://www.bilibili.com/video/BV123", cards.single().playbackURL)
        assertEquals("https://i0.hdslb.com/a.jpg", cards.single().thumbnailURL)
    }

    @Test
    fun youtubeInitialDataBecomesNativeCardsWithoutOpeningAWebList() {
        val html = """{"videoRenderer":{"videoId":"abc123","thumbnail":{"thumbnails":[{"url":"https://i.ytimg.com/vi/abc123/hqdefault.jpg"}]},"title":{"runs":[{"text":"官方動畫"}]},"ownerText":{"runs":[{"text":"官方頻道"}]}}}"""
        val cards = NativeMediaParser.youtube(html)
        assertEquals("官方動畫", cards.single().title)
        assertEquals("https://www.youtube.com/watch?v=abc123", cards.single().playbackURL)
    }

    @Test
    fun thumbnailRequestOnlyLoadsSafeHttpImages() {
        assertTrue(NetworkThumbnailRequest("https://i.example/card.jpg").isLoadable)
        assertTrue(NetworkThumbnailRequest("http://i.example/card.jpg").isLoadable)
        assertFalse(NetworkThumbnailRequest("").isLoadable)
        assertFalse(NetworkThumbnailRequest("file:///tmp/private.jpg").isLoadable)
    }

    @Test
    fun mediaScreenFocusClampsAndReturnsToTabs() {
        var state = NativeMediaState(cardCount = 9, gridColumns = 4)
        state = state.reduce(RemoteCommand.Down).reduce(RemoteCommand.Down)
        assertEquals(4, state.focusedCard)
        state = state.reduce(RemoteCommand.Right)
        assertEquals(5, state.focusedCard)
        state = state.reduce(RemoteCommand.Up)
        assertEquals(1, state.focusedCard)
        state = state.reduce(RemoteCommand.Up)
        assertEquals(true, state.isTopNavigationFocused)
    }
}
