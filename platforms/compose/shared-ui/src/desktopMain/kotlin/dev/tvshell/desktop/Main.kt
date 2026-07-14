package dev.tvshell.desktop

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
import dev.tvshell.shared.BilibiliSection
import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.ShellPreferences
import dev.tvshell.shared.platformLoadPreferences
import dev.tvshell.shared.platformSavePreferences
import dev.tvshell.shared.anime.ServiceCredentialsParser
import dev.tvshell.shared.anime.platformChooseAndInstallCredentials
import dev.tvshell.shared.anime.platformCredentialsFile
import dev.tvshell.shared.anime.AnimeEpisode
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.DanmakuComment
import dev.tvshell.shared.anime.DesktopAnimeService
import dev.tvshell.shared.RemoteCommandDispatcher
import dev.tvshell.shared.desktopKeyToRemoteCommand
import java.io.File
import java.net.HttpURLConnection
import java.net.URI

fun main() = application {
    val remoteDispatcher = remember { RemoteCommandDispatcher() }
    Window(
        onCloseRequest = ::exitApplication,
        title = "TVShell",
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
        val platformAdapter = remember { WindowsPlatformAdapter() }
        TVShellApp(platformAdapter, dispatcher = remoteDispatcher)
    }
}

private class WindowsPlatformAdapter : PlatformAdapter {
    private val animeServices = DesktopAnimeService { platformLoadPreferences() }
    override fun installedApps(): List<ShellApp> {
        val roots = listOfNotNull(
            System.getenv("ProgramData")?.let { File(it, "Microsoft/Windows/Start Menu/Programs") },
            System.getenv("APPDATA")?.let { File(it, "Microsoft/Windows/Start Menu/Programs") },
        )
        return roots.asSequence()
            .filter(File::isDirectory)
            .flatMap { it.walkTopDown().asSequence() }
            .filter { it.isFile && (it.extension.equals("lnk", true) || it.extension.equals("exe", true)) }
            .distinctBy { it.absolutePath.lowercase() }
            .take(80)
            .map { ShellApp("windows:${it.absolutePath}", it.nameWithoutExtension, "Windows App", executable = it.absolutePath) }
            .toList()
    }

    override fun launch(app: ShellApp): Result<Unit> = runCatching {
        val executable = requireNotNull(app.executable) { "這是 TVShell 內建 App，尚未接上此平台服務。" }
        ProcessBuilder("cmd", "/c", "start", "", executable).start()
    }

    override fun openSystemSettings(): Result<Unit> = runCatching {
        ProcessBuilder("cmd", "/c", "start", "", "ms-settings:").start()
    }

    override fun openCredentialsImporter(): Result<Unit> = runCatching {
        platformChooseAndInstallCredentials()
    }
    override fun credentialsLocation(): String = platformCredentialsFile().absolutePath
    override fun loadPreferences(): Result<ShellPreferences> = runCatching { platformLoadPreferences() }
    override fun savePreferences(preferences: ShellPreferences): Result<Unit> = runCatching { platformSavePreferences(preferences) }

    override fun fetchMediaFeed(service: NativeMediaService): Result<List<NativeMediaCard>> = runCatching {
        val url = when (service) {
            NativeMediaService.YouTube -> "https://www.youtube.com/results?search_query=%E5%8B%95%E7%95%AB&hl=zh-TW&gl=TW"
            NativeMediaService.Bilibili -> "https://api.bilibili.com/x/web-interface/popular?ps=30&pn=1"
        }
        val body = fetchText(url)
        when (service) {
            NativeMediaService.YouTube -> NativeMediaParser.youtube(body)
            NativeMediaService.Bilibili -> NativeMediaParser.bilibili(body)
        }.ifEmpty { error("服務沒有回傳可顯示的影片") }
    }

    override fun fetchBilibiliSection(section: BilibiliSection): Result<List<NativeMediaCard>> = runCatching {
        val credentials = loadCredentials()
        val cookie = credentials.bilibiliCookie
        val authenticated = cookie.contains("SESSDATA=") && cookie.contains("bili_jct=") && cookie.contains("DedeUserID=")
        val endpoint = when (section) {
            BilibiliSection.Recommended -> "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd?fresh_type=3&ps=30"
            BilibiliSection.Popular -> "https://api.bilibili.com/x/web-interface/popular?ps=30&pn=1"
            BilibiliSection.Ranking -> "https://api.bilibili.com/x/web-interface/ranking/v2?rid=0&type=all"
            BilibiliSection.Dynamic -> {
                require(authenticated) { "Cookie 缺少 SESSDATA、bili_jct 或 DedeUserID；請在 credentials.json 匯入完整 bilibili.com Cookie" }
                "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all"
            }
            BilibiliSection.Profile -> {
                require(authenticated) { "Cookie 缺少 SESSDATA、bili_jct 或 DedeUserID；請在 credentials.json 匯入完整 bilibili.com Cookie" }
                "https://api.bilibili.com/x/web-interface/nav"
            }
        }
        val body = fetchText(endpoint, if (cookie.isBlank()) emptyMap() else mapOf("Cookie" to cookie))
        NativeMediaParser.bilibiliFailureReason(body)?.let(::error)
        when (section) {
            BilibiliSection.Dynamic -> NativeMediaParser.bilibiliDynamic(body)
            BilibiliSection.Profile -> NativeMediaParser.bilibiliProfile(body)
            else -> NativeMediaParser.bilibili(body)
        }.ifEmpty { error("Bilibili ${section.title}沒有回傳可顯示內容") }
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

    override fun playMedia(card: NativeMediaCard): Result<Unit> = runCatching {
        ProcessBuilder("cmd", "/c", "start", "", card.playbackURL).start()
    }

    override fun fetchWallpaperURL(): Result<String> = runCatching {
        BingWallpaperMetadata.imageURL(fetchText("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW"))
            ?: error("Bing 沒有回傳圖片")
    }

    private fun fetchText(url: String, headers: Map<String, String> = emptyMap()): String {
        val connection = (URI(url).toURL().openConnection() as HttpURLConnection).apply {
            instanceFollowRedirects = true
            requestMethod = "GET"
            connectTimeout = 8_000
            readTimeout = 8_000
            setRequestProperty("User-Agent", "Mozilla/5.0 TVShell/1.0")
            setRequestProperty("Accept-Language", "zh-TW,zh;q=0.9,en;q=0.7")
            setRequestProperty("Referer", "https://www.bilibili.com/")
            headers.forEach(::setRequestProperty)
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
        val candidates = listOfNotNull(
            System.getenv("TVSHELL_CREDENTIALS_FILE")?.let(::File),
            platformCredentialsFile(),
            File(System.getProperty("user.home"), "credentials.json"),
            File("credentials.json"),
        )
        val stored = candidates.firstOrNull(File::isFile)?.let {
            runCatching { ServiceCredentialsParser.decode(it.readText()) }.getOrNull()
        } ?: dev.tvshell.shared.anime.ServiceCredentials()
        val environmentCookie = System.getenv("TVSHELL_BILIBILI_COOKIE").orEmpty()
        return if (environmentCookie.isBlank()) stored else stored.copy(bilibiliCookie = environmentCookie)
    }
}
