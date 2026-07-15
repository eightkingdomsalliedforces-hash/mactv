package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.SwingPanel
import java.awt.BorderLayout
import javax.swing.JPanel
import javax.swing.SwingUtilities
import javafx.application.Platform
import javafx.concurrent.Worker
import javafx.embed.swing.JFXPanel
import javafx.scene.Scene
import javafx.scene.web.WebEngine
import javafx.scene.web.WebView
import javafx.util.Callback

@Composable
actual fun PlatformWebSurface(
    url: String,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier,
) {
    val latestExit = rememberUpdatedState(onExitRequested)
    val holder = remember { DesktopWebSurfaceHolder { latestExit.value() } }
    SwingPanel(
        factory = { holder.container },
        modifier = modifier,
    )
    LaunchedEffect(url) { holder.load(url) }
    LaunchedEffect(signal.sequence) {
        if (signal.sequence > 0) holder.dispatch(signal.command)
    }
    DisposableEffect(Unit) {
        onDispose(holder::dispose)
    }
}

private class DesktopWebSurfaceHolder(private val exit: () -> Unit) {
    private val fxPanel = JFXPanel()
    val container = JPanel(BorderLayout()).apply { add(fxPanel, BorderLayout.CENTER) }
    private var engine: WebEngine? = null
    private var pendingURL: String? = null

    init {
        Platform.setImplicitExit(false)
        Platform.runLater {
            val webView = WebView().apply {
                isContextMenuEnabled = false
                engine.userAgent = "${engine.userAgent} TVShell/1.0 WindowsTV"
            }
            webView.engine.createPopupHandler = Callback { webView.engine }
            webView.engine.loadWorker.stateProperty().addListener { _, _, state ->
                if (state == Worker.State.SUCCEEDED) runCatching { webView.engine.executeScript(WebRemoteScripts.pagePreparation) }
            }
            engine = webView.engine
            fxPanel.scene = Scene(webView)
            pendingURL?.let(webView.engine::load)
            pendingURL = null
        }
    }

    fun load(url: String) {
        pendingURL = url
        Platform.runLater {
            engine?.let {
                if (it.location != url) it.load(url)
                pendingURL = null
            }
        }
    }

    fun dispatch(command: WebRuntimeCommand) {
        Platform.runLater {
            val current = engine ?: return@runLater
            if (command == WebRuntimeCommand.Back) {
                val history = current.history
                if (history.currentIndex > 0) history.go(-1) else SwingUtilities.invokeLater(exit)
            } else {
                runCatching { current.executeScript(WebRemoteScripts.command(command)) }
            }
        }
    }

    fun dispose() {
        Platform.runLater { engine?.load("about:blank") }
    }
}
