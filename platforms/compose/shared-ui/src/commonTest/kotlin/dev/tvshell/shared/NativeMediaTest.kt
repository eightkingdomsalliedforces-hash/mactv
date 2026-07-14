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
    fun bilibiliBangumiRankingBecomesAnimeCards() {
        val json = """{"result":{"list":[{"cover":"https://i0.hdslb.com/bangumi.jpg","new_ep":{"index_show":"更新至第12話"},"rating":"9.7分","season_id":12345,"title":"葬送的芙莉蓮"}]}}"""
        val card = NativeMediaParser.bilibiliBangumi(json).single()
        assertEquals("葬送的芙莉蓮", card.title)
        assertEquals("9.7分 · 更新至第12話", card.subtitle)
        assertEquals("https://www.bilibili.com/bangumi/play/ss12345", card.playbackURL)
    }

    @Test
    fun bilibiliBangumiMetadataDoesNotLeakBetweenRankingItems() {
        val json = """{"result":{"list":[{"badge":"","cover":"https://i0/one.jpg","new_ep":{"cover":"https://i0/one-ep.jpg","index_show":"更新至第43話"},"rating":"9.7分","season_id":1,"title":"第一部"},{"badge":"","cover":"https://i0/two.jpg","new_ep":{"cover":"https://i0/two-ep.jpg","index_show":"全1266話"},"rating":"9.8分","season_id":2,"title":"第二部"}]}}"""
        val cards = NativeMediaParser.bilibiliBangumi(json)
        assertEquals(listOf("9.7分 · 更新至第43話", "9.8分 · 全1266話"), cards.map(NativeMediaCard::subtitle))
        assertEquals(listOf("https://i0/one.jpg", "https://i0/two.jpg"), cards.map(NativeMediaCard::thumbnailURL))
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
    fun bilibiliThumbnailsCarryTheRequiredReferer() {
        val request = NetworkThumbnailRequest("https://i0.hdslb.com/bfs/bangumi/cover.jpg")
        assertEquals("https://www.bilibili.com/", request.headers["Referer"])
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
