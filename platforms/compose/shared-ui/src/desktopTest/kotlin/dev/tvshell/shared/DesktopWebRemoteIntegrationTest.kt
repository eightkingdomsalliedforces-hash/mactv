package dev.tvshell.shared

import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javafx.application.Platform
import javafx.concurrent.Worker
import javafx.embed.swing.JFXPanel
import javafx.scene.Scene
import javafx.scene.web.WebView
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopWebRemoteIntegrationTest {
    @Test
    fun windowsNativeAnimeCommandsReachTheVisiblePlayerSurface() {
        val app = File("src/commonMain/kotlin/dev/tvshell/shared/TVShellApp.kt").readText()
        val surface = File("src/desktopMain/kotlin/dev/tvshell/shared/PlatformAnimeVideoSurface.desktop.kt").readText()

        assertTrue(app.contains("animeWebState = animeWebState.reduce(RemoteCommand.PlayPause)"))
        assertTrue(app.contains("animeWebState = animeWebState.reduce(if (seconds >= 0) RemoteCommand.FastForward else RemoteCommand.Rewind)"))
        assertTrue(surface.contains("holder.dispatch(signal.command)"))
        assertTrue(!app.contains("adapter.playAnime().fold"))
        assertTrue(!app.contains("adapter.seekAnimeBy(seconds).fold"))
    }

    @Test
    fun directionMovesDomFocusAndSelectClicksTheFocusedControl() {
        val ready = CountDownLatch(1)
        val completed = CountDownLatch(1)
        var focusedID = ""
        var clicked = false

        val panel = JFXPanel()
        Platform.setImplicitExit(false)
        Platform.runLater {
            val webView = WebView().apply {
                prefWidth = 800.0
                prefHeight = 500.0
            }
            panel.scene = Scene(webView, 800.0, 500.0)
            webView.engine.loadWorker.stateProperty().addListener { _, _, state ->
                if (state != Worker.State.SUCCEEDED) return@addListener
                ready.countDown()
                // SUCCEEDED can arrive before the first WebView layout pulse on Linux.
                // Real remote input happens after layout, so exercise the same timing.
                Platform.runLater {
                    runCatching {
                        webView.engine.executeScript(WebRemoteScripts.pagePreparation)
                        webView.engine.executeScript("document.getElementById('left').focus()")
                        webView.engine.executeScript(WebRemoteScripts.command(WebRuntimeCommand.ScrollRight))
                        focusedID = webView.engine.executeScript("document.activeElement.id")?.toString().orEmpty()
                        webView.engine.executeScript(WebRemoteScripts.command(WebRuntimeCommand.Select))
                        clicked = webView.engine.executeScript("window.clicked === true") == true
                    }
                    completed.countDown()
                }
            }
            webView.engine.loadContent(
                """
                <html><body style='margin:0;width:800px;height:500px'>
                  <button id='left' style='position:absolute;left:80px;top:200px;width:120px;height:60px'>Left</button>
                  <button id='right' onclick='window.clicked=true' style='position:absolute;left:560px;top:200px;width:120px;height:60px'>Right</button>
                </body></html>
                """.trimIndent(),
            )
        }

        assertTrue(ready.await(5, TimeUnit.SECONDS), "JavaFX page did not load")
        assertTrue(completed.await(5, TimeUnit.SECONDS), "JavaFX remote script did not complete")
        assertEquals("right", focusedID)
        assertTrue(clicked)
    }
}
