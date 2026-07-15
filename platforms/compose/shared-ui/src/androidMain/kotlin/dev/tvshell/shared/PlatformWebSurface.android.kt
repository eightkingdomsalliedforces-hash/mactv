package dev.tvshell.shared

import android.annotation.SuppressLint
import android.graphics.Color
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView

@SuppressLint("SetJavaScriptEnabled")
@Composable
actual fun PlatformWebSurface(
    url: String,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier,
) {
    var webView by remember { mutableStateOf<WebView?>(null) }
    val requestedURLPolicy = remember { RequestedURLPolicy(url) }
    val latestExit by rememberUpdatedState(onExitRequested)
    AndroidView(
        factory = { context ->
            WebView(context).apply webView@ {
                setBackgroundColor(Color.BLACK)
                isVerticalScrollBarEnabled = false
                isHorizontalScrollBarEnabled = false
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.builtInZoomControls = false
                settings.displayZoomControls = false
                settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                settings.mediaPlaybackRequiresUserGesture = false
                settings.userAgentString = "${settings.userAgentString} TVShell/1.0 AndroidTV"
                CookieManager.getInstance().apply {
                    setAcceptCookie(true)
                    setAcceptThirdPartyCookies(this@webView, true)
                }
                webChromeClient = WebChromeClient()
                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, loadedURL: String) {
                        view.evaluateJavascript(WebRemoteScripts.pagePreparation, null)
                    }
                }
                loadUrl(url)
                webView = this
            }
        },
        update = { view ->
            webView = view
            if (requestedURLPolicy.shouldLoad(url)) view.loadUrl(url)
        },
        modifier = modifier,
    )
    LaunchedEffect(signal.sequence) {
        if (signal.sequence == 0L) return@LaunchedEffect
        val view = webView ?: return@LaunchedEffect
        if (signal.command == WebRuntimeCommand.Back) {
            if (view.canGoBack()) view.goBack() else latestExit()
        } else {
            view.evaluateJavascript(WebRemoteScripts.command(signal.command), null)
        }
    }
    DisposableEffect(Unit) {
        onDispose {
            webView?.apply {
                stopLoading()
                loadUrl("about:blank")
                destroy()
            }
            webView = null
        }
    }
}
