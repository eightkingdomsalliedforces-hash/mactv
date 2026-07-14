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
import dev.tvshell.shared.ShellPreferences
import dev.tvshell.shared.platformLoadPreferences
import dev.tvshell.shared.platformSavePreferences
import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.RemoteCommandDispatcher
import dev.tvshell.shared.desktopKeyToRemoteCommand
import dev.tvshell.shared.anime.BTRssParser
import dev.tvshell.shared.anime.AnimeEpisode
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.BilibiliAnimeParser
import dev.tvshell.shared.anime.CSS1HtmlParser
import dev.tvshell.shared.anime.CSS1Resolver
import dev.tvshell.shared.anime.PlatformCSS1ContentClient
import dev.tvshell.shared.anime.DandanplayService
import dev.tvshell.shared.anime.DandanplayCredentials
import dev.tvshell.shared.anime.DanmakuComment
import dev.tvshell.shared.anime.ServiceCredentialsParser
import dev.tvshell.shared.anime.platformSHA256Base64
import dev.tvshell.shared.anime.platformChooseAndInstallCredentials
import dev.tvshell.shared.anime.platformCredentialsFile
import dev.tvshell.shared.anime.DesktopVLCPlayerAdapter
import java.net.HttpURLConnection
import java.net.URI
import java.io.File
import kotlin.system.exitProcess
import kotlinx.coroutines.runBlocking

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
    private val animeServices = dev.tvshell.shared.anime.DesktopAnimeService {
        loadPreferences().getOrDefault(ShellPreferences())
    }
    override fun installedApps(): List<ShellApp> = emptyList()
    override fun launch(app: ShellApp): Result<Unit> = Result.failure(IllegalStateException("請先在動畫 App 內設定來源"))
    override fun openSystemSettings(): Result<Unit> = Result.success(Unit)
    override fun openCredentialsImporter(): Result<Unit> = runCatching { platformChooseAndInstallCredentials() }
    override fun credentialsLocation(): String = platformCredentialsFile().absolutePath
    override fun loadPreferences(): Result<ShellPreferences> = runCatching { platformLoadPreferences() }
    override fun savePreferences(preferences: ShellPreferences): Result<Unit> = runCatching { platformSavePreferences(preferences) }
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
    override fun fetchAnimeFeed(source: AnimeSourceKind): Result<List<NativeMediaCard>> = animeServices.feed(source)
    override fun fetchAnimeEpisodes(source: AnimeSourceKind, card: NativeMediaCard): Result<List<AnimeEpisode>> = animeServices.episodes(source, card)
    override fun resolveAnimeStreams(source: AnimeSourceKind, episode: AnimeEpisode): Result<List<AnimeStreamCandidate>> = animeServices.streams(source, episode)
    override fun loadAnimeStream(candidate: AnimeStreamCandidate): Result<Unit> = animeServices.load(candidate)
    override fun playAnime(): Result<Unit> = animeServices.play()
    override fun pauseAnime(): Result<Unit> = animeServices.pause()
    override fun seekAnimeBy(seconds: Int): Result<Unit> = animeServices.seekBy(seconds)
    override fun adjustAnimeVolume(direction: Int): Result<Unit> = animeServices.volume(direction)
    override fun stopAnime(): Result<Unit> = animeServices.stop()
    override fun fetchAnimeDanmaku(
        source: AnimeSourceKind,
        card: NativeMediaCard,
        episode: AnimeEpisode,
    ): Result<List<DanmakuComment>> = animeServices.danmaku(source, card, episode)
    override fun playMedia(card: NativeMediaCard): Result<Unit> = Result.success(Unit)
    override fun exitApp(): Result<Unit> = runCatching { exitProcess(0) }
    override fun fetchWallpaperURL(): Result<String> = runCatching {
        BingWallpaperMetadata.imageURL(fetchText("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW"))
            ?: error("Bing 沒有回傳圖片")
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

    private fun loadCredentials(): dev.tvshell.shared.anime.ServiceCredentials {
        val environment = DandanplayCredentials(
            System.getenv("TVSHELL_DANDANPLAY_APP_ID").orEmpty(),
            System.getenv("TVSHELL_DANDANPLAY_APP_SECRET").orEmpty(),
        )
        val files = listOfNotNull(
            System.getenv("TVSHELL_CREDENTIALS_FILE")?.let(::File),
            platformCredentialsFile(),
            File(System.getProperty("user.home"), "credentials.json"),
            File("credentials.json"),
        )
        val stored = files.firstOrNull(File::isFile)?.let { runCatching { ServiceCredentialsParser.decode(it.readText()) }.getOrNull() }
            ?: dev.tvshell.shared.anime.ServiceCredentials()
        return if (environment.isConfigured) stored.copy(dandanplay = environment) else stored
    }
}
