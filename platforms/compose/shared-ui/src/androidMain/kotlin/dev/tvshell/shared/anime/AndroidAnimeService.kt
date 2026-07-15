package dev.tvshell.shared.anime

import android.content.Context
import android.media.AudioManager
import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.NativeMediaCard
import dev.tvshell.shared.NativeMediaParser
import dev.tvshell.shared.ShellPreferences
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking

class AndroidAnimeService(
    private val context: Context,
    private val preferences: () -> ShellPreferences,
) : PlatformAnimeService {
    override val capabilities = AnimePlatformCapabilities(css1 = true, danmaku = true, internalPlayer = true)
    override val css1SubscriptionURL: String get() = preferences().animeSources.css1SubscriptionURL
    private val client = PlatformCSS1ContentClient()
    private val player = AndroidMediaPlayerAdapter(context)
    private val dandanplay = DandanplayService(client, ::platformSHA256Base64)
    private val torrentEngine: TorrentPlaybackEngine = AndroidTorrentPlaybackEngine(File(context.cacheDir, "TVShell/Torrents"))
    private var resolverURL: String? = null
    private var css1Resolver: CSS1Resolver? = null

    override fun feed(source: AnimeSourceKind): Result<List<NativeMediaCard>> = when (source) {
        AnimeSourceKind.YouTube -> publicFeed(source, "https://www.youtube.com/results?search_query=%E5%AE%98%E6%96%B9%E5%8B%95%E7%95%AB&hl=zh-TW&gl=TW") {
            NativeMediaParser.youtube(it)
        }
        AnimeSourceKind.Bilibili -> publicFeed(source, "https://api.bilibili.com/pgc/web/rank/list?season_type=1&day=3") {
            NativeMediaParser.bilibiliBangumi(it)
        }
        AnimeSourceKind.BangumiYouTube, AnimeSourceKind.AniSubsBT -> runCatching {
            BangumiMetadataParser.calendar(fetchText("https://api.bgm.tv/calendar"))
                .map(BangumiSubjectMetadata::asCard).ifEmpty { error("Bangumi 沒有回傳本週動畫資料") }
                .map { it.copy(animeSource = source) }
        }
        AnimeSourceKind.CSS1 -> if (!preferences().animeSources.css1Enabled) {
            Result.failure(IllegalStateException("CSS1 已在動漫來源設定中停用"))
        } else publicFeed(source, "https://api.bilibili.com/pgc/web/rank/list?season_type=1&day=3") {
            NativeMediaParser.bilibiliBangumi(it)
        }
        AnimeSourceKind.AniGamer -> Result.success(listOf(
            NativeMediaCard(
                "anigamer-official",
                "動畫瘋",
                "官方網站 · 保留廣告、登入與地區限制",
                "",
                "https://ani.gamer.com.tw/",
                source,
            ),
        ))
        AnimeSourceKind.Mikan -> rssFeed(source, "TVSHELL_MIKAN_RSS_URL", "Mikan")
        AnimeSourceKind.DMHY -> rssFeed(source, "TVSHELL_DMHY_RSS_URL", "動漫花園")
    }

    override fun episodes(source: AnimeSourceKind, card: NativeMediaCard): Result<List<AnimeEpisode>> = when (source) {
        AnimeSourceKind.Bilibili -> runCatching {
            val seasonID = card.id.substringAfter("bilibili-season-", "").takeIf(String::isNotBlank)
                ?: card.playbackURL.substringAfter("/ss", "").substringBefore('?').takeIf(String::isNotBlank)
                ?: error("缺少 Bilibili season_id")
            BilibiliAnimeParser.episodes(fetchText("https://api.bilibili.com/pgc/web/season/section?season_id=$seasonID"))
                .ifEmpty { error("Bilibili 沒有回傳選集") }
        }
        AnimeSourceKind.CSS1 -> runCatching { runBlocking {
            val direct = resolver().episodes(card.title)
            if (direct.isNotEmpty()) direct else {
                searchBangumi(card.title).firstOrNull()?.aliases.orEmpty()
                    .filterNot { it.equals(card.title, ignoreCase = true) }
                    .firstNotNullOfOrNull { alias -> resolver().episodes(alias).takeIf(List<AnimeEpisode>::isNotEmpty) }
                    ?: error("CSS1 搜不到：${card.title}（Bangumi 別名也沒有結果）")
            }
        } }
        AnimeSourceKind.BangumiYouTube -> runCatching {
            val subjectID = card.id.substringAfter("bangumi-").toIntOrNull() ?: error("Bangumi 作品識別格式錯誤")
            val metadata = BangumiMetadataParser.subject(fetchText("https://api.bgm.tv/v0/subjects/$subjectID"))
            val count = (metadata?.episodeCount ?: card.episodeCount ?: 1).coerceAtLeast(1)
            (1..count).map { number -> AnimeEpisode("${card.id}:$number", "${metadata?.title ?: card.title} 第 $number 話", number, card.playbackURL) }
        }
        AnimeSourceKind.AniSubsBT -> runCatching {
            MagnetHistoryReplay.episode(card)?.let(::listOf) ?: run {
                val subjectID = card.id.substringAfter("bangumi-").toIntOrNull() ?: error("Bangumi 作品識別格式錯誤")
                val metadata = BangumiMetadataParser.subject(fetchText("https://api.bgm.tv/v0/subjects/$subjectID"))
                val count = (metadata?.episodeCount ?: card.episodeCount ?: 1).coerceAtLeast(1)
                (1..count).map { number -> AnimeEpisode("${card.id}:$number", "${metadata?.title ?: card.title} 第 $number 話", number, card.playbackURL) }
            }
        }
        else -> {
            val number = card.animeEpisodeNumber ?: 1
            Result.success(listOf(AnimeEpisode("${source.name.lowercase()}:${card.id}", "第 $number 集", number, card.playbackURL)))
        }
    }

    override fun streams(source: AnimeSourceKind, episode: AnimeEpisode): Result<List<AnimeStreamCandidate>> = when (source) {
        AnimeSourceKind.Bilibili -> runCatching {
            val fields = episode.id.split(':')
            require(fields.size >= 3) { "Bilibili 選集識別格式錯誤" }
            val payload = fetchText("https://api.bilibili.com/pgc/player/web/playurl?ep_id=${fields[1]}&cid=${fields[2]}&qn=80&fnver=0&fnval=0&fourk=0")
            BilibiliAnimeParser.failureReason(payload)?.let(::error)
            BilibiliAnimeParser.streams(payload).ifEmpty { error("Bilibili 沒有可用播放網址，可能需要登入或會員權限") }
        }
        AnimeSourceKind.CSS1 -> runCatching { runBlocking {
            resolver().streams(episode).ifEmpty { error("CSS1 選集解析失敗：沒有可用播放源") }
        } }
        AnimeSourceKind.AniGamer, AnimeSourceKind.YouTube -> Result.success(
            listOf(AnimeStreamCandidate(episode.pageURL, "官方播放器", mapOf("resolver" to "official"))),
        )
        AnimeSourceKind.BangumiYouTube -> Result.success(listOf(
            AnimeStreamCandidate(
                "https://www.youtube.com/results?search_query=${URLEncoder.encode(episode.title, StandardCharsets.UTF_8.name())}&hl=zh-TW",
                "Bangumi + YouTube",
                mapOf("resolver" to "official"),
            ),
        ))
        AnimeSourceKind.AniSubsBT -> MagnetHistoryReplay.stream(episode)?.let { Result.success(listOf(it)) }
            ?: aniSubsStreams(episode)
        AnimeSourceKind.Mikan, AnimeSourceKind.DMHY -> Result.success(
            listOf(AnimeStreamCandidate(episode.pageURL, "BT / RSS", mapOf("resolver" to "torrent"))),
        )
    }

    override fun load(candidate: AnimeStreamCandidate): Result<Unit> = runCatching {
        require(candidate.url.startsWith("magnet:", ignoreCase = true).not() && candidate.headers["resolver"] != "torrent") {
            "magnet 必須先由內建 BT 引擎解析，不能直接交給播放器"
        }
        if (candidate.headers["resolver"] != "official") {
            player.load(candidate)
            player.play()
        }
    }
    override fun startTorrent(request: TorrentStartRequest): Result<Long> = torrentEngine.start(request)
    override fun torrentSnapshot(): TorrentTransferSnapshot = torrentEngine.snapshot()
    override fun consumeTorrentPlayableStream(generation: Long): TorrentPlayableStream? = torrentEngine.consumeReadyStream(generation)
    override fun cancelTorrentAutoplay(generation: Long) = torrentEngine.cancelAutoplay(generation)
    override fun torrentDownloads(): Result<List<TorrentCachedDownload>> = runCatching { torrentEngine.cachedDownloads() }
    override fun deleteTorrentDownload(id: String): Result<Unit> = torrentEngine.deleteCachedDownload(id)
    override fun play(): Result<Unit> = runCatching { player.play() }
    override fun pause(): Result<Unit> = runCatching { player.pause() }
    override fun seekBy(seconds: Int): Result<Unit> = runCatching { player.seekBy(seconds) }
    override fun volume(direction: Int): Result<Unit> = runCatching {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustStreamVolume(
            AudioManager.STREAM_MUSIC,
            if (direction >= 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
            AudioManager.FLAG_SHOW_UI,
        )
    }
    override fun mute(): Result<Unit> = runCatching {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_TOGGLE_MUTE, AudioManager.FLAG_SHOW_UI)
    }
    override fun stop(): Result<Unit> = runCatching { player.release() }
    override fun playbackSnapshot(): AnimePlaybackSnapshot = player.snapshot()
    override fun close() {
        player.close()
        torrentEngine.close()
    }

    override fun danmaku(
        source: AnimeSourceKind,
        card: NativeMediaCard,
        episode: AnimeEpisode,
    ): Result<List<DanmakuComment>> = runCatching { runBlocking {
        if (source == AnimeSourceKind.Bilibili) {
            val cid = episode.id.split(':').getOrNull(2) ?: error("Bilibili 選集缺少 cid，無法讀取彈幕")
            BilibiliAnimeParser.danmaku(fetchText("https://api.bilibili.com/x/v1/dm/list.so?oid=$cid"))
        } else {
            dandanplay.comments(card.title, episode.number, loadCredentials().dandanplay, (System.currentTimeMillis() / 1_000).toInt())
        }
    } }

    private fun resolver(): CSS1Resolver {
        val url = css1SubscriptionURL
        if (css1Resolver == null || resolverURL != url) {
            resolverURL = url
            css1Resolver = CSS1Resolver(client, url)
        }
        return requireNotNull(css1Resolver)
    }

    private fun publicFeed(source: AnimeSourceKind, url: String, parse: (String) -> List<NativeMediaCard>): Result<List<NativeMediaCard>> = runCatching {
        parse(fetchText(url)).map { it.copy(animeSource = source) }.ifEmpty { error("來源沒有回傳可播放內容") }
    }

    private fun rssFeed(source: AnimeSourceKind, environmentKey: String, displayName: String): Result<List<NativeMediaCard>> = runCatching {
        val url = System.getenv(environmentKey)?.takeIf(String::isNotBlank)
            ?: error("尚未設定 $displayName RSS（$environmentKey）")
        BTRssParser.items(fetchText(url)).map { item ->
            NativeMediaCard(
                item.magnet,
                item.title,
                listOfNotNull(item.quality, item.episode?.let { "第 $it 集" }).joinToString(" · ").ifBlank { displayName },
                "",
                item.magnet,
                source,
                animeEpisodeNumber = item.episode,
            )
        }.ifEmpty { error("$displayName 沒有回傳可用項目") }
    }

    private fun aniSubsStreams(episode: AnimeEpisode): Result<List<AnimeStreamCandidate>> = runCatching {
        val sources = AniSubsBTSubscriptionParser.sources(fetchText(ANISUBS_BT_SUBSCRIPTION_URL))
        require(sources.isNotEmpty()) { "ani-subs BT 訂閱沒有可用 RSS 搜尋來源" }
        val keyword = episode.title.replace(Regex("\\s*第\\s*\\d+\\s*[集話话].*$"), "").trim()
        runBlocking {
            sources.map { source ->
                async(Dispatchers.IO) {
                    runCatching {
                        val url = AniSubsBTSearch.queryURL(source.searchURLTemplate, keyword)
                        AniSubsBTSearch.candidates(source.name, fetchText(url), episode.number)
                    }.getOrDefault(emptyList())
                }
            }.awaitAll().flatten()
        }.distinctBy(AnimeStreamCandidate::url).ifEmpty {
            error("ani-subs BT 搜不到第 ${episode.number} 集")
        }
    }

    private fun fetchText(url: String): String {
        val connection = URL(url).openConnection() as HttpURLConnection
        return try {
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android TV) TVShell/1.0")
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

    private fun searchBangumi(keyword: String): List<BangumiSubjectMetadata> {
        val body = "{\"keyword\":\"${keyword.replace("\\", "\\\\").replace("\"", "\\\"")}\",\"filter\":{\"type\":[2]}}"
        val connection = URL("https://api.bgm.tv/v0/search/subjects?limit=30").openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "TVShell/1.0 (Android TV; Bangumi metadata client)")
            connection.outputStream.use { it.write(body.toByteArray(StandardCharsets.UTF_8)) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            require(status in 200..299 && stream != null) { "Bangumi HTTP $status" }
            BangumiMetadataParser.subjects(stream.bufferedReader().use { it.readText() })
        } finally {
            connection.disconnect()
        }
    }

    private fun loadCredentials(): ServiceCredentials {
        val files = listOfNotNull(
            File(context.filesDir, "credentials.json"),
            context.getExternalFilesDir(null)?.let { File(it, "credentials.json") },
        )
        return files.firstOrNull(File::isFile)?.let {
            runCatching { ServiceCredentialsParser.decode(it.readText()) }.getOrNull()
        } ?: ServiceCredentials()
    }
}

private const val ANISUBS_BT_SUBSCRIPTION_URL = "https://sub.creamycake.org/v1/bt1.json"
