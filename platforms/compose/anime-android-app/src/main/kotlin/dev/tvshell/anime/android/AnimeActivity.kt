package dev.tvshell.anime.android

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import android.view.KeyEvent
import android.content.Context
import android.media.AudioManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts
import dev.tvshell.shared.PlatformAdapter
import dev.tvshell.shared.AndroidTVKeyMapper
import dev.tvshell.shared.RemoteCommandDispatcher
import dev.tvshell.shared.ShellApp
import dev.tvshell.shared.NativeMediaCard
import dev.tvshell.shared.NativeMediaParser
import dev.tvshell.shared.NativeMediaService
import dev.tvshell.shared.TVShellApp
import dev.tvshell.shared.BingWallpaperMetadata
import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.ShellPreferences
import dev.tvshell.shared.ShellPreferencesCodec
import dev.tvshell.shared.anime.AndroidMediaPlayerAdapter
import dev.tvshell.shared.anime.AnimeEpisode
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.BilibiliAnimeParser
import dev.tvshell.shared.anime.CSS1HtmlParser
import dev.tvshell.shared.anime.CSS1Resolver
import dev.tvshell.shared.anime.PlatformCSS1ContentClient
import dev.tvshell.shared.anime.DandanplayService
import dev.tvshell.shared.anime.DanmakuComment
import dev.tvshell.shared.anime.ServiceCredentials
import dev.tvshell.shared.anime.ServiceCredentialsParser
import dev.tvshell.shared.anime.platformSHA256Base64
import java.net.HttpURLConnection
import java.net.URL
import java.io.File
import kotlinx.coroutines.runBlocking

class AnimeActivity : ComponentActivity() {
    private val remoteDispatcher = RemoteCommandDispatcher()
    private lateinit var platformAdapter: AnimePlatformAdapter
    private val credentialsPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && ::platformAdapter.isInitialized) platformAdapter.importCredentials(uri)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        platformAdapter = AnimePlatformAdapter(this) {
            credentialsPicker.launch(arrayOf("application/json", "text/plain", "text/*"))
        }
        onBackPressedDispatcher.addCallback(this) {
            remoteDispatcher.dispatch(dev.tvshell.shared.RemoteCommand.Back)
        }
        setContent { TVShellApp(platformAdapter, animeOnly = true, dispatcher = remoteDispatcher) }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        AndroidTVKeyMapper.command(keyCode, event.isLongPress)?.let {
            remoteDispatcher.dispatch(it)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}

private class AnimePlatformAdapter(
    private val activity: ComponentActivity,
    private val chooseCredentials: () -> Unit,
) : PlatformAdapter {
    private val animeServices = dev.tvshell.shared.anime.AndroidAnimeService(activity) {
        loadPreferences().getOrDefault(ShellPreferences())
    }
    override fun installedApps(): List<ShellApp> = emptyList()
    override fun launch(app: ShellApp): Result<Unit> = Result.failure(IllegalStateException("請先在動畫 App 內設定來源"))
    override fun openSystemSettings(): Result<Unit> = runCatching {
        activity.startActivity(Intent(Settings.ACTION_SETTINGS))
    }
    override fun openCredentialsImporter(): Result<Unit> = runCatching { chooseCredentials() }
    override fun credentialsLocation(): String = credentialsFile().absolutePath
    override fun loadPreferences(): Result<ShellPreferences> = runCatching {
        preferencesFile().takeIf(File::isFile)?.let { ShellPreferencesCodec.decode(it.readText()) } ?: ShellPreferences()
    }
    override fun savePreferences(preferences: ShellPreferences): Result<Unit> = runCatching {
        val file = preferencesFile()
        val temporary = File(file.parentFile, "${file.name}.tmp")
        temporary.writeText(ShellPreferencesCodec.encode(preferences))
        if (file.exists() && !file.delete()) error("無法更新 TVShell 設定檔")
        if (!temporary.renameTo(file)) error("無法儲存 TVShell 設定檔")
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
    override fun exitApp(): Result<Unit> = runCatching { activity.finish() }
    override fun fetchWallpaperURL(): Result<String> = runCatching {
        val connection = URL("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW").openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        val body = try { connection.inputStream.bufferedReader().use { it.readText() } } finally { connection.disconnect() }
        BingWallpaperMetadata.imageURL(body) ?: error("Bing 沒有回傳圖片")
    }

    private fun fetchText(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) AppleWebKit/537.36 Chrome/125 Safari/537.36")
            connection.setRequestProperty("Accept", "application/json,text/html,*/*")
            connection.setRequestProperty("Accept-Language", "zh-TW,zh;q=0.9,en;q=0.7")
            if (url.contains("bilibili.com")) connection.setRequestProperty("Referer", "https://www.bilibili.com/")
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            require(status in 200..299 && stream != null) { "HTTP $status" }
            stream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun loadCredentials(): ServiceCredentials {
        val candidates = listOfNotNull(
            File(activity.filesDir, "credentials.json"),
            activity.getExternalFilesDir(null)?.let { File(it, "credentials.json") },
        )
        return candidates.firstOrNull(File::isFile)?.let {
            runCatching { ServiceCredentialsParser.decode(it.readText()) }.getOrNull()
        } ?: ServiceCredentials()
    }

    private fun credentialsFile(): File = File(activity.filesDir, "credentials.json")
    private fun preferencesFile(): File = File(activity.filesDir, "preferences.json")

    fun importCredentials(uri: Uri) {
        runCatching {
            val destination = credentialsFile()
            activity.contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use(input::copyTo)
            } ?: error("無法讀取選擇的憑證檔案")
            val parsed = ServiceCredentialsParser.decode(destination.readText())
            require(parsed.bilibiliCookie.isNotBlank() || parsed.dandanplay.isConfigured) {
                "檔案中找不到 Bilibili Cookie 或 Dandanplay 憑證"
            }
        }.onFailure { it.printStackTrace() }
    }
}
