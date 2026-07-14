package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.DesktopMediaProxy
import java.awt.BorderLayout
import javafx.application.Platform
import javafx.embed.swing.JFXPanel
import javafx.scene.Group
import javafx.scene.Scene
import javafx.scene.media.Media
import javafx.scene.media.MediaPlayer
import javafx.scene.media.MediaView
import javafx.util.Duration
import javax.swing.JPanel

@Composable
actual fun PlatformAnimeVideoSurface(
    candidate: AnimeStreamCandidate?,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier,
) {
    val holder = remember { DesktopAnimeMediaHolder() }
    SwingPanel(factory = { holder.container }, modifier = modifier)
    LaunchedEffect(candidate?.url) { candidate?.let(holder::load) }
    LaunchedEffect(signal.sequence) {
        if (signal.sequence > 0) holder.dispatch(signal.command)
    }
    DisposableEffect(Unit) { onDispose(holder::dispose) }
}

private class DesktopAnimeMediaHolder {
    private val fxPanel = JFXPanel()
    val container = JPanel(BorderLayout()).apply { add(fxPanel, BorderLayout.CENTER) }
    private var player: MediaPlayer? = null
    private var mediaView: MediaView? = null

    init {
        Platform.setImplicitExit(false)
        Platform.runLater {
            val view = MediaView().apply { isPreserveRatio = true }
            val root = Group(view)
            val scene = Scene(root)
            view.fitWidthProperty().bind(scene.widthProperty())
            view.fitHeightProperty().bind(scene.heightProperty())
            mediaView = view
            fxPanel.scene = scene
        }
    }

    fun load(candidate: AnimeStreamCandidate) {
        val playbackURL = DesktopMediaProxy.playbackURL(candidate)
        Platform.runLater {
            player?.dispose()
            player = MediaPlayer(Media(playbackURL)).also { next ->
                mediaView?.mediaPlayer = next
                next.play()
            }
        }
    }

    fun dispatch(command: WebRuntimeCommand) {
        Platform.runLater {
            val current = player ?: return@runLater
            when (command) {
                WebRuntimeCommand.PlayPause, WebRuntimeCommand.Select -> {
                    if (current.status == MediaPlayer.Status.PLAYING) current.pause() else current.play()
                }
                WebRuntimeCommand.Rewind -> current.seek(current.currentTime.subtract(Duration.seconds(15.0)).coerceAtLeast(Duration.ZERO))
                WebRuntimeCommand.FastForward -> current.seek(current.currentTime.add(Duration.seconds(15.0)).coerceAtMost(current.totalDuration))
                WebRuntimeCommand.VolumeUp -> current.volume = (current.volume + .1).coerceAtMost(1.0)
                WebRuntimeCommand.VolumeDown -> current.volume = (current.volume - .1).coerceAtLeast(0.0)
                else -> Unit
            }
        }
    }

    fun dispose() {
        Platform.runLater {
            player?.stop()
            player?.dispose()
            player = null
        }
    }
}

private fun Duration.coerceAtLeast(minimum: Duration): Duration = if (lessThan(minimum)) minimum else this
private fun Duration.coerceAtMost(maximum: Duration): Duration = when {
    maximum.isUnknown || maximum.isIndefinite -> this
    greaterThan(maximum) -> maximum
    else -> this
}
