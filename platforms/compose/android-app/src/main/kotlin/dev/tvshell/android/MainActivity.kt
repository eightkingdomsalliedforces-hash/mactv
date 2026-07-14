package dev.tvshell.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import android.net.Uri
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.addCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
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
import dev.tvshell.shared.BilibiliSection
import dev.tvshell.shared.ShellPreferences
import dev.tvshell.shared.ShellPreferencesCodec
import dev.tvshell.shared.anime.ServiceCredentialsParser
import dev.tvshell.shared.anime.AndroidAnimeService
import dev.tvshell.shared.anime.AnimeEpisode
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.DanmakuComment
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : ComponentActivity() {
    private var appsRevision by mutableIntStateOf(0)
    private val remoteDispatcher = RemoteCommandDispatcher()
    private lateinit var platformAdapter: AndroidTVPlatformAdapter
    private val credentialsPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && ::platformAdapter.isInitialized) platformAdapter.importCredentials(uri)
    }
    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            appsRevision += 1
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        platformAdapter = AndroidTVPlatformAdapter(
            this,
            packageManager,
            packageName,
            ::startActivity,
        ) { credentialsPicker.launch(arrayOf("application/json", "text/plain", "text/*")) }
        onBackPressedDispatcher.addCallback(this) {
            remoteDispatcher.dispatch(dev.tvshell.shared.RemoteCommand.Back)
        }
        setContent {
            TVShellApp(
                platformAdapter,
                appsRevision = appsRevision,
                dispatcher = remoteDispatcher,
            )
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val command = AndroidTVKeyMapper.command(keyCode, event.isLongPress)
        if (command != null) {
            remoteDispatcher.dispatch(command)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(packageReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(packageReceiver, filter)
        }
    }

    override fun onStop() {
        unregisterReceiver(packageReceiver)
        super.onStop()
    }
}

private class AndroidTVPlatformAdapter(
    private val context: Context,
    private val packageManager: PackageManager,
    private val ownPackageName: String,
    private val startActivity: (Intent) -> Unit,
    private val chooseCredentials: () -> Unit,
) : PlatformAdapter {
    private val animeServices = AndroidAnimeService(context) {
        preferencesFile().takeIf(File::isFile)?.let { ShellPreferencesCodec.decode(it.readText()) } ?: ShellPreferences()
    }
    override fun installedApps(): List<ShellApp> {
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
        return packageManager.queryIntentActivities(query, PackageManager.MATCH_ALL)
            .asSequence()
            .filter { it.activityInfo.packageName != ownPackageName }
            .distinctBy { it.activityInfo.packageName }
            .map { info ->
                ShellApp(
                    id = "android:${info.activityInfo.packageName}",
                    name = info.loadLabel(packageManager).toString(),
                    subtitle = "Android TV App",
                    packageName = info.activityInfo.packageName,
                )
            }
            .sortedBy { it.name.lowercase() }
            .toList() + ShellApp("android-settings", "Android 設定", "安全出口", isSystemSettings = true)
    }

    override fun launch(app: ShellApp): Result<Unit> = runCatching {
        val packageName = requireNotNull(app.packageName) { "這是 TVShell 內建 App，尚未接上此平台服務。" }
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
            ?: packageManager.getLaunchIntentForPackage(packageName)
            ?: error("找不到可啟動的 Activity")
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    override fun openSystemSettings(): Result<Unit> = runCatching {
        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
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

    fun importCredentials(uri: Uri) {
        val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            ?: error("無法讀取選擇的憑證檔案")
        val parsed = ServiceCredentialsParser.decode(text)
        require(parsed.bilibiliCookie.isNotBlank() || parsed.dandanplay.isConfigured) {
            "檔案中找不到 Bilibili Cookie 或 Dandanplay 憑證"
        }
        credentialsFile().writeText(text)
    }

    override fun fetchMediaFeed(service: NativeMediaService): Result<List<NativeMediaCard>> = runCatching {
        val endpoint = when (service) {
            NativeMediaService.YouTube -> "https://www.youtube.com/results?search_query=%E5%8B%95%E7%95%AB&hl=zh-TW&gl=TW"
            NativeMediaService.Bilibili -> "https://api.bilibili.com/x/web-interface/popular?ps=30&pn=1"
        }
        val connection = URL(endpoint).openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        connection.setRequestProperty("User-Agent", "Mozilla/5.0 TVShell/1.0")
        val body = connection.inputStream.bufferedReader().use { it.readText() }
        when (service) {
            NativeMediaService.YouTube -> NativeMediaParser.youtube(body)
            NativeMediaService.Bilibili -> NativeMediaParser.bilibili(body)
        }.ifEmpty { error("服務沒有回傳可顯示的影片") }
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

    override fun fetchBilibiliSection(section: BilibiliSection): Result<List<NativeMediaCard>> = runCatching {
        val credentials = credentialsFile().takeIf(File::isFile)?.let {
            runCatching { ServiceCredentialsParser.decode(it.readText()) }.getOrNull()
        }
        val cookie = credentials?.bilibiliCookie.orEmpty()
        val authenticated = cookie.contains("SESSDATA=") && cookie.contains("bili_jct=") && cookie.contains("DedeUserID=")
        val endpoint = when (section) {
            BilibiliSection.Recommended -> "https://api.bilibili.com/x/web-interface/index/top/feed/rcmd?fresh_type=3&ps=30"
            BilibiliSection.Popular -> "https://api.bilibili.com/x/web-interface/popular?ps=30&pn=1"
            BilibiliSection.Ranking -> "https://api.bilibili.com/x/web-interface/ranking/v2?rid=0&type=all"
            BilibiliSection.Dynamic -> {
                require(authenticated) { "Cookie 缺少 SESSDATA、bili_jct 或 DedeUserID；請在設定匯入完整 bilibili.com Cookie" }
                "https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all"
            }
            BilibiliSection.Profile -> {
                require(authenticated) { "Cookie 缺少 SESSDATA、bili_jct 或 DedeUserID；請在設定匯入完整 bilibili.com Cookie" }
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

    override fun playMedia(card: NativeMediaCard): Result<Unit> = Result.success(Unit)

    override fun fetchWallpaperURL(): Result<String> = runCatching {
        val connection = URL("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=zh-TW").openConnection() as HttpURLConnection
        connection.connectTimeout = 8_000
        connection.readTimeout = 8_000
        val body = try { connection.inputStream.bufferedReader().use { it.readText() } } finally { connection.disconnect() }
        BingWallpaperMetadata.imageURL(body) ?: error("Bing 沒有回傳圖片")
    }

    private fun credentialsFile(): File = File(context.filesDir, "credentials.json")
    private fun preferencesFile(): File = File(context.filesDir, "preferences.json")

    private fun fetchText(url: String, headers: Map<String, String>): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) TVShell/1.0")
            connection.setRequestProperty("Referer", "https://www.bilibili.com/")
            for ((name, value) in headers) connection.setRequestProperty(name, value)
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            require(status in 200..299 && stream != null) { "HTTP $status" }
            stream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }
}
