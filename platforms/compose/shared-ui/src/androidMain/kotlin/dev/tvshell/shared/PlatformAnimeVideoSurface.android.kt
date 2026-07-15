package dev.tvshell.shared

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
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
    val surfaceOwner = remember { Any() }
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestExit = rememberUpdatedState(onExitRequested)
    LaunchedEffect(candidate?.url, candidate?.headers) {
        candidate?.let {
            player?.load(it)
            player?.play()
        }
    }
    LaunchedEffect(signal.sequence) {
        if (signal.sequence == 0L) return@LaunchedEffect
        if (signal.command == WebRuntimeCommand.Back) {
            latestExit.value()
            return@LaunchedEffect
        }
        when (signal.command.nativePlayerAction()) {
            NativePlayerAction.TogglePlayback -> if (player?.snapshot()?.isPlaying == true) player.pause() else player?.play()
            NativePlayerAction.SeekBackward -> player?.seekBy(-15)
            NativePlayerAction.SeekForward -> player?.seekBy(15)
            NativePlayerAction.VolumeUp -> player?.adjustVolume(.1f)
            NativePlayerAction.VolumeDown -> player?.adjustVolume(-.1f)
            NativePlayerAction.ToggleMute -> player?.toggleMute()
            null -> Unit
        }
    }
    AndroidView(
        factory = { context ->
            SurfaceView(context).also { view ->
                view.holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        player?.attachSurface(surfaceOwner, holder.surface)
                    }
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                        player?.attachSurface(surfaceOwner, holder.surface)
                    }
                    override fun surfaceDestroyed(holder: SurfaceHolder) {
                        player?.detachSurface(surfaceOwner)
                    }
                })
            }
        },
        modifier = modifier,
    )
    DisposableEffect(player, lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) player?.pause()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            player?.detachSurface(surfaceOwner, pauseIfOwned = true)
        }
    }
}
