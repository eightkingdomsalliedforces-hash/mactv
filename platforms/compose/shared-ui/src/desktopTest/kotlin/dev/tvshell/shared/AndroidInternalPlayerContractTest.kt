package dev.tvshell.shared

import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AndroidInternalPlayerContractTest {
    @Test
    fun androidUsesMedia3ForAdaptiveAndTorrentPlayback() {
        val source = File("src/androidMain/kotlin/dev/tvshell/shared/anime/AndroidAnimePlatform.kt").readText()
        val build = File("build.gradle.kts").readText()
        val notices = File("../package-resources/common/ThirdPartyNotices.txt").readText()

        assertTrue(source.contains("androidx.media3.exoplayer.ExoPlayer"))
        assertTrue(source.contains("DefaultMediaSourceFactory"))
        assertFalse(source.contains("android.media.MediaPlayer"))
        assertTrue(build.contains("media3-exoplayer-hls"))
        assertTrue(build.contains("media3-exoplayer-dash"))
        assertTrue(notices.contains("AndroidX Media3 1.10.1"))
    }

    @Test
    fun androidPlayerTeardownCannotPauseANewerSurfaceOrLeakMuteState() {
        val source = File("src/androidMain/kotlin/dev/tvshell/shared/anime/AndroidAnimePlatform.kt").readText()
        val surface = File("src/androidMain/kotlin/dev/tvshell/shared/PlatformAnimeVideoSurface.android.kt").readText()

        assertTrue(source.contains("fun detachSurface(owner: Any, pauseIfOwned: Boolean = false)"))
        assertTrue(source.contains("if (!surfaceLease.detach(owner)) return@post"))
        assertTrue(source.contains("if (pauseIfOwned) player?.pause()"))
        assertTrue(surface.contains("detachSurface(surfaceOwner, pauseIfOwned = true)"))
        assertTrue(source.contains("volume = 1f"))
        assertTrue(source.contains("muted = false"))
    }
}
