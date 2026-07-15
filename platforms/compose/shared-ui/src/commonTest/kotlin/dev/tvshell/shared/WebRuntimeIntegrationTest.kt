package dev.tvshell.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

class WebRuntimeIntegrationTest {
    @Test
    fun browserDirectionsMoveDomFocusInsteadOfOnlyScrollingTheWindow() {
        val preparation = WebRemoteScripts.pagePreparation

        assertTrue(preparation.contains("__tvshellRemoteMove"))
        assertTrue(preparation.contains("scrollIntoView"))
        assertTrue(preparation.contains("focus("))
        assertTrue(WebRemoteScripts.command(WebRuntimeCommand.ScrollDown).contains("__tvshellRemoteMove('down')"))
        assertTrue(WebRemoteScripts.command(WebRuntimeCommand.Select).contains("__tvshellRemoteSelect"))
    }

    @Test
    fun directMediaUsesNativeSurfaceWhileProviderPagesUseEmbeddedPlayers() {
        val direct = NativePlaybackTargetResolver.resolve(
            NativeMediaCard("movie", "Movie", "", "", "https://cdn.example.test/movie.m3u8"),
        )
        val youtube = NativePlaybackTargetResolver.resolve(
            NativeMediaCard("yt", "Video", "", "", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
        )
        val bilibili = NativePlaybackTargetResolver.resolve(
            NativeMediaCard("bili", "Video", "", "", "https://www.bilibili.com/video/BV1xx411c7mD"),
        )

        assertIs<NativePlaybackTarget.Direct>(direct)
        assertEquals("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1&playsinline=1", assertIs<NativePlaybackTarget.Embedded>(youtube).url)
        assertEquals("https://player.bilibili.com/player.html?bvid=BV1xx411c7mD&autoplay=1&high_quality=1", assertIs<NativePlaybackTarget.Embedded>(bilibili).url)
    }

    @Test
    fun nativePlayerRemoteCommandsMapToRealPlaybackActions() {
        assertEquals(NativePlayerAction.TogglePlayback, WebRuntimeCommand.PlayPause.nativePlayerAction())
        assertEquals(NativePlayerAction.SeekBackward, WebRuntimeCommand.Rewind.nativePlayerAction())
        assertEquals(NativePlayerAction.SeekForward, WebRuntimeCommand.FastForward.nativePlayerAction())
        assertEquals(NativePlayerAction.VolumeUp, WebRuntimeCommand.VolumeUp.nativePlayerAction())
        assertEquals(NativePlayerAction.VolumeDown, WebRuntimeCommand.VolumeDown.nativePlayerAction())
        assertEquals(NativePlayerAction.ToggleMute, WebRuntimeCommand.Mute.nativePlayerAction())
    }

    @Test
    fun rootFocusIsRequestedOnceAfterTheUiNodeIsAttached() {
        val bootstrap = RootFocusBootstrap()
        var requests = 0

        assertTrue(bootstrap.requestOnce { requests += 1 })
        assertFalse(bootstrap.requestOnce { requests += 1 })
        assertEquals(1, requests)
    }

    @Test
    fun browserOnlyReloadsWhenTheRequestedUrlActuallyChanges() {
        val policy = RequestedURLPolicy("https://example.test/start")

        assertFalse(policy.shouldLoad("https://example.test/start"))
        assertFalse(policy.shouldLoad("https://example.test/start"))
        assertTrue(policy.shouldLoad("https://example.test/other"))
        assertFalse(policy.shouldLoad("https://example.test/other"))
    }

    @Test
    fun staleSurfaceCannotDetachTheNewPlayerSurface() {
        val lease = OwnedValue<String>()
        val oldOwner = Any()
        val newOwner = Any()

        lease.attach(oldOwner, "old")
        lease.attach(newOwner, "new")

        assertFalse(lease.detach(oldOwner))
        assertEquals("new", lease.value)
        assertTrue(lease.detach(newOwner))
        assertEquals(null, lease.value)
    }

    @Test
    fun visiblePlayerSurfaceReceivesOneCommandSignal() {
        val state = WebRuntimeState("https://cdn.example.test/video.m3u8")
        val signaled = state.reduce(RemoteCommand.FastForward)

        assertEquals(1L, signaled.signal.sequence)
        assertEquals(WebRuntimeCommand.FastForward, signaled.signal.command)
    }
}
