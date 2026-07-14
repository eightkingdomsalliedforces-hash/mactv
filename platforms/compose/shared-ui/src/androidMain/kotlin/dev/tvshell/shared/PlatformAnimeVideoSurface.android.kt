package dev.tvshell.shared

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import dev.tvshell.shared.anime.AndroidAnimePlaybackRegistry
import dev.tvshell.shared.anime.AnimeStreamCandidate

@Composable
actual fun PlatformAnimeVideoSurface(
    candidate: AnimeStreamCandidate?,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier,
) {
    val player = AndroidAnimePlaybackRegistry.player
    AndroidView(
        factory = { context ->
            SurfaceView(context).also { view ->
                view.holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        player?.attachSurface(holder.surface)
                    }
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                        player?.attachSurface(holder.surface)
                    }
                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        player?.attachSurface(null)
                    }
                })
            }
        },
        modifier = modifier,
    )
    DisposableEffect(player) {
        onDispose { player?.attachSurface(null) }
    }
}
