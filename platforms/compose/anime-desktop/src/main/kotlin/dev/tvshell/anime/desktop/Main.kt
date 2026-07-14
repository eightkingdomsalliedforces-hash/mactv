package dev.tvshell.anime.desktop

import androidx.compose.runtime.remember
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.rememberWindowState
import androidx.compose.ui.window.application
import dev.tvshell.shared.PlatformAdapter
import dev.tvshell.shared.NativeMediaCard
import dev.tvshell.shared.NativeMediaParser
import dev.tvshell.shared.NativeMediaService
import dev.tvshell.shared.ShellApp
import dev.tvshell.shared.TVShellApp
import dev.tvshell.shared.BingWallpaperMetadata
import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.RemoteCommandDispatcher
import dev.tvshell.shared.desktopKeyToRemoteCommand
import dev.tvshell.shared.anime.BTRssParser
import dev.tvshell.shared.anime.CSS1HtmlParser
import java.net.HttpURLConnection
import java.net.URI
import kotlin.system.exitProcess

fun main() = application {
    val remoteDispatcher = remember { RemoteCommandDispatcher() }
    Window(
        onCloseRequest = ::exitApplication,
        title = "TVShell 動畫",
        undecorated = true,
        state = rememberWindowState(placement = WindowPlacement.Maximized),
        onPreviewKeyEvent = { event ->
            if (event.type != KeyEventType.KeyDown) false
            else desktopKeyToRemoteCommand(event.key, event.isShiftPressed)?.let {
                remoteDispatcher.dispatch(it)
                true
            } ?: false
        },
    ) {
        TVShellApp(AnimeDesktopAdapter, animeOnly = true, dispatcher = remoteDispatcher)
    }
}

private object AnimeDesktopAdapter : PlatformAdapter {
    override fun installedApps(): List<ShellApp> = emptyList()
    override fun launch(app: ShellApp): Result<Unit> = Result.failure(IllegalStateException("請先在動畫 App 內設定來源"))
    override fun openSystemSettings(): Result<Unit> = Result.success(Unit)
    override fun fetchMediaFeed(service: NativeMediaService): Result<List<NativeMediaCard>> = runCatching {
        val endpoint = when (service) {
            NativeMediaService.YouTube -> "https://www.youtube.com/results?search_query=%E5%AE%98%E6%96%B9%E5%8B%95%E7%95%AB&hl=zh-TW&gl=TW"
            NativeMediaService.Bilibili -> "https://api.bilibili.com/pgc/web/rank/list?season_type=1&day=3"
        }
        val body = fetchText(endpoint)
        when (service) {
            NativeMediaService.YouTube -> NativeMediaParser.youtube(body)
            NativeMediaService.Bilibili -> NativeMediaParser.bilibiliBangumi(body)
        }.ifEmpty { error("來源沒有回傳可播放內容") }
    }
    override fun fetchAnimeFeed(source: AnimeSourceKind): Result<List<NativeMediaCard>> = when (source) {
        AnimeSourceKind.YouTube -> fetchMediaFeed(NativeMediaService.YouTube)
        AnimeSourceKind.Bilibili -> fetchMediaFeed(NativeMediaService.Bilibili)
        AnimeSourceKind.AniGamer -> super<PlatformAdapter>.fetchAnimeFeed(source)
        AnimeSourceKind.CSS1 -> selectorFeed("TVSHELL_ANISUBS_CSS1_URL", "CSS1")
        AnimeSourceKind.AniSubsBT -> rssFeed("TVSHELL_ANISUBS_BT_URL", "ani-subs BT")
        AnimeSourceKind.Mikan -> rssFeed("TVSHELL_MIKAN_RSS_URL", "Mikan")
        AnimeSourceKind.DMHY -> rssFeed("TVSHELL_DMHY_RSS_URL", "動漫花園")
    }
    override fun playMedia(card: NativeMediaCard): Result<Unit> = runCatching {
        ProcessBuilder("cmd", "/c", "start", "", card.playbackURL).start()
    }
    override fun exitApp(): Result<Unit> = runCatching { exitProcess(0) }
    override fun fetchWallpaperURL(): Result<String> = runCatching {
        BingWallpaperMetadata.imageURL(fetchText("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW"))
            ?: error("Bing 沒有回傳圖片")
    }

    private fun selectorFeed(environmentKey: String, displayName: String): Result<List<NativeMediaCard>> = runCatching {
        val url = System.getenv(environmentKey)?.takeIf(String::isNotBlank)
            ?: error("尚未設定 $displayName 訂閱網址（$environmentKey）")
        CSS1HtmlParser.titles(fetchText(url), url).map { title ->
            NativeMediaCard(title.id, title.title, displayName, "", title.detailURL)
        }.ifEmpty { error("$displayName 沒有回傳可用作品") }
    }

    private fun rssFeed(environmentKey: String, displayName: String): Result<List<NativeMediaCard>> = runCatching {
        val url = System.getenv(environmentKey)?.takeIf(String::isNotBlank)
            ?: error("尚未設定 $displayName RSS（$environmentKey）")
        BTRssParser.items(fetchText(url)).map { item ->
            NativeMediaCard(
                id = item.magnet,
                title = item.title,
                subtitle = listOfNotNull(item.quality, item.episode?.let { "第 $it 集" }).joinToString(" · ").ifBlank { displayName },
                thumbnailURL = "",
                playbackURL = item.magnet,
            )
        }.ifEmpty { error("$displayName 沒有回傳可用項目") }
    }

    private fun fetchText(url: String): String {
        val connection = (URI(url).toURL().openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            requestMethod = "GET"
            connectTimeout = 8_000
            readTimeout = 8_000
            setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125 Safari/537.36")
            setRequestProperty("Accept-Language", "zh-TW,zh;q=0.9,en;q=0.7")
            setRequestProperty("Accept", "application/json,text/plain,*/*")
            if (url.contains("bilibili.com")) {
                setRequestProperty("Referer", "https://search.bilibili.com/")
            }
        }
        return try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            require(status in 200..299 && stream != null) { "HTTP $status" }
            stream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}
