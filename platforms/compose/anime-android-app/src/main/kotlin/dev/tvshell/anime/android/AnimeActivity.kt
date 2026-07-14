package dev.tvshell.anime.android

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import dev.tvshell.shared.PlatformAdapter
import dev.tvshell.shared.AndroidTVKeyMapper
import dev.tvshell.shared.RemoteCommandDispatcher
import dev.tvshell.shared.ShellApp
import dev.tvshell.shared.NativeMediaCard
import dev.tvshell.shared.NativeMediaParser
import dev.tvshell.shared.NativeMediaService
import dev.tvshell.shared.TVShellApp
import dev.tvshell.shared.BingWallpaperMetadata
import java.net.HttpURLConnection
import java.net.URL

class AnimeActivity : ComponentActivity() {
    private val remoteDispatcher = RemoteCommandDispatcher()
    private var longBackDispatched = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TVShellApp(AnimePlatformAdapter(this), animeOnly = true, dispatcher = remoteDispatcher) }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount > 0 && event.isLongPress) {
                longBackDispatched = true
                remoteDispatcher.dispatch(dev.tvshell.shared.RemoteCommand.Home)
                return true
            }
            if (event.action == KeyEvent.ACTION_DOWN) return true
            if (event.action == KeyEvent.ACTION_UP) {
                if (longBackDispatched) longBackDispatched = false
                else remoteDispatcher.dispatch(dev.tvshell.shared.RemoteCommand.Back)
                return true
            }
        }
        if (event.action == KeyEvent.ACTION_DOWN) {
            AndroidTVKeyMapper.command(event.keyCode, event.isLongPress)?.let {
                remoteDispatcher.dispatch(it)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }
}

private class AnimePlatformAdapter(private val activity: ComponentActivity) : PlatformAdapter {
    override fun installedApps(): List<ShellApp> = emptyList()
    override fun launch(app: ShellApp): Result<Unit> = Result.failure(IllegalStateException("請先在動畫 App 內設定來源"))
    override fun openSystemSettings(): Result<Unit> = runCatching {
        activity.startActivity(Intent(Settings.ACTION_SETTINGS))
    }
    override fun fetchMediaFeed(service: NativeMediaService): Result<List<NativeMediaCard>> = runCatching {
        val endpoint = when (service) {
            NativeMediaService.YouTube -> "https://www.youtube.com/results?search_query=%E5%AE%98%E6%96%B9%E5%8B%95%E7%95%AB&hl=zh-TW&gl=TW"
            NativeMediaService.Bilibili -> "https://api.bilibili.com/pgc/web/rank/list?season_type=1&day=3"
        }
        val connection = URL(endpoint).openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/125 Safari/537.36")
        connection.setRequestProperty("Accept", "application/json,text/plain,*/*")
        connection.setRequestProperty("Accept-Language", "zh-TW,zh;q=0.9,en;q=0.7")
        if (endpoint.contains("bilibili.com")) {
            connection.setRequestProperty("Referer", "https://search.bilibili.com/")
        }
        val body = connection.inputStream.bufferedReader().use { it.readText() }
        when (service) {
            NativeMediaService.YouTube -> NativeMediaParser.youtube(body)
            NativeMediaService.Bilibili -> NativeMediaParser.bilibiliBangumi(body)
        }.ifEmpty { error("來源沒有回傳可播放內容") }
    }
    override fun playMedia(card: NativeMediaCard): Result<Unit> = runCatching {
        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(card.playbackURL)))
    }
    override fun exitApp(): Result<Unit> = runCatching { activity.finish() }
    override fun fetchWallpaperURL(): Result<String> = runCatching {
        val connection = URL("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW").openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        val body = try { connection.inputStream.bufferedReader().use { it.readText() } } finally { connection.disconnect() }
        BingWallpaperMetadata.imageURL(body) ?: error("Bing 沒有回傳圖片")
    }
}
