package dev.tvshell.shared

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

enum class NativeMediaService { YouTube, Bilibili }
enum class BilibiliSection(val title: String) {
    Recommended("推薦"), Popular("熱門"), Ranking("排行榜"), Dynamic("動態"), Profile("我的")
}

data class NativeMediaCard(
    val id: String,
    val title: String,
    val subtitle: String,
    val thumbnailURL: String,
    val playbackURL: String,
    val animeSource: AnimeSourceKind? = null,
    val alternateTitles: List<String> = emptyList(),
    val episodeCount: Int? = null,
    val animeEpisodeNumber: Int? = null,
)

sealed interface NativePlaybackTarget {
    data class Direct(val candidate: dev.tvshell.shared.anime.AnimeStreamCandidate) : NativePlaybackTarget
    data class Embedded(val url: String) : NativePlaybackTarget
}

object NativePlaybackTargetResolver {
    private val directExtensions = setOf("mp4", "m4v", "mov", "mkv", "webm", "avi", "m3u8", "mpd", "ts")
    private val youtubeID = Regex("(?:youtube(?:-nocookie)?\\.com/(?:watch\\?v=|embed/)|youtu\\.be/)([A-Za-z0-9_-]{6,})")
    private val bilibiliID = Regex("(?:bilibili\\.com/video/|bvid=)(BV[A-Za-z0-9]+)", RegexOption.IGNORE_CASE)

    fun resolve(card: NativeMediaCard): NativePlaybackTarget {
        val rawURL = card.playbackURL.trim()
        youtubeID.find(rawURL)?.groupValues?.getOrNull(1)?.let { id ->
            return NativePlaybackTarget.Embedded("https://www.youtube-nocookie.com/embed/$id?autoplay=1&playsinline=1")
        }
        bilibiliID.find(rawURL)?.groupValues?.getOrNull(1)?.let { id ->
            return NativePlaybackTarget.Embedded("https://player.bilibili.com/player.html?bvid=$id&autoplay=1&high_quality=1")
        }
        val path = rawURL.substringBefore('?').substringBefore('#')
        val extension = path.substringAfterLast('.', "").lowercase()
        if (extension in directExtensions || rawURL.startsWith("http://127.0.0.1:") || rawURL.startsWith("http://localhost:")) {
            return NativePlaybackTarget.Direct(
                dev.tvshell.shared.anime.AnimeStreamCandidate(rawURL, "內建播放器", emptyMap()),
            )
        }
        return NativePlaybackTarget.Embedded(rawURL)
    }
}

data class WatchHistoryState(
    val entries: List<NativeMediaCard> = emptyList(),
) {
    fun record(card: NativeMediaCard): WatchHistoryState = copy(
        entries = (listOf(card) + entries.filter { it.id != card.id }).take(8),
    )

    fun delete(id: String): WatchHistoryState = copy(entries = entries.filterNot { it.id == id })
    fun clear(): WatchHistoryState = copy(entries = emptyList())
}

enum class NativeMediaPhase { Browser, Player }

data class NativeMediaState(
    val cardCount: Int,
    val tabCount: Int = 4,
    val gridColumns: Int = 4,
    val phase: NativeMediaPhase = NativeMediaPhase.Browser,
    val focusedTab: Int = 0,
    val focusedCard: Int = 0,
    val isTopNavigationFocused: Boolean = true,
    val isPlaying: Boolean = true,
    val pendingSeekSeconds: Int = 0,
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): NativeMediaState = when (phase) {
        NativeMediaPhase.Browser -> when {
            isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedTab = (focusedTab - 1).coerceAtLeast(0))
            isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedTab = (focusedTab + 1).coerceAtMost((tabCount - 1).coerceAtLeast(0)))
            isTopNavigationFocused && command == RemoteCommand.Down && cardCount > 0 -> copy(isTopNavigationFocused = false)
            !isTopNavigationFocused && command == RemoteCommand.Up && focusedCard < gridColumns -> copy(isTopNavigationFocused = true)
            !isTopNavigationFocused && command == RemoteCommand.Up -> copy(focusedCard = (focusedCard - gridColumns).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Down -> copy(focusedCard = (focusedCard + gridColumns).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedCard = (focusedCard - 1).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedCard = (focusedCard + 1).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Select -> copy(phase = NativeMediaPhase.Player, pendingAction = "open-internal:$focusedCard", pendingSeekSeconds = 0, isPlaying = true)
            else -> this
        }
        NativeMediaPhase.Player -> when (command) {
            RemoteCommand.PlayPause, RemoteCommand.Select -> copy(isPlaying = !isPlaying)
            RemoteCommand.FastForward, RemoteCommand.Right -> copy(pendingSeekSeconds = pendingSeekSeconds + 15)
            RemoteCommand.Rewind, RemoteCommand.Left -> copy(pendingSeekSeconds = pendingSeekSeconds - 15)
            RemoteCommand.Back, RemoteCommand.Home -> copy(phase = NativeMediaPhase.Browser, pendingSeekSeconds = 0, pendingAction = null)
            else -> this
        }
    }

    fun clearAction() = copy(pendingAction = null)
}

object NativeMediaParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun bilibiliBangumi(payload: String): List<NativeMediaCard> {
        val blocks = Regex("\\\"season_id\\\"\\s*:").findAll(payload).map { match ->
            val badgeStart = payload.lastIndexOf("{\"badge\"", match.range.first)
            val coverStart = payload.lastIndexOf("{\"cover\"", match.range.first)
            val start = badgeStart.takeIf { it >= 0 } ?: coverStart.takeIf { it >= 0 } ?: match.range.first
            payload.substring(start, (start + 6_000).coerceAtMost(payload.length))
        }
        return blocks.mapNotNull { block ->
            val seasonID = numberField(block, "season_id") ?: return@mapNotNull null
            val title = field(block.substringAfter("\"season_id\":"), "title") ?: return@mapNotNull null
            val cover = normalizeImage(field(block, "cover").orEmpty())
            val rating = field(block, "rating").orEmpty()
            val progress = field(block.substringAfter("\"new_ep\":"), "index_show").orEmpty()
            val subtitle = listOf(rating, progress).filter(String::isNotBlank).joinToString(" · ").ifBlank { "Bilibili 番劇" }
            NativeMediaCard(
                id = "bilibili-season-$seasonID",
                title = clean(title),
                subtitle = clean(subtitle),
                thumbnailURL = cover,
                playbackURL = "https://www.bilibili.com/bangumi/play/ss$seasonID",
            )
        }.distinctBy { it.id }.take(24).toList()
    }

    fun bilibiliFailureReason(payload: String): String? {
        val root = runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return null
        val code = root.numberText("code")?.toIntOrNull() ?: return null
        if (code == 0) return null
        return root.stringValue("message")?.takeIf(String::isNotBlank) ?: "Bilibili API 錯誤 $code"
    }

    fun bilibili(payload: String): List<NativeMediaCard> {
        val blocks = Regex("\"bvid\"\\s*:").findAll(payload).map { match ->
            val starts = listOf("{\"aid\"", "{\"type\"").map { payload.lastIndexOf(it, match.range.first) }
            val start = starts.maxOrNull()?.takeIf { it >= 0 } ?: match.range.first
            payload.substring(start, (start + 6_000).coerceAtMost(payload.length))
        }.toList()
        return blocks.mapNotNull { block ->
            val id = field(block, "bvid") ?: return@mapNotNull null
            val title = field(block, "title") ?: return@mapNotNull null
            val image = normalizeImage(field(block, "pic").orEmpty())
            val owner = field(block.substringAfter("\"owner\":", ""), "name") ?: field(block, "author") ?: "Bilibili"
            NativeMediaCard(id, clean(title), clean(owner), image, "https://www.bilibili.com/video/$id")
        }.distinctBy { it.id }
    }

    fun youtube(payload: String): List<NativeMediaCard> {
        val blocks = payload.split("\"videoRenderer\":").drop(1).map { it.take(6_000) }
        return blocks.mapNotNull { block ->
            val id = field(block, "videoId") ?: return@mapNotNull null
            val titleArea = block.substringAfter("\"title\":", "")
            val title = field(titleArea, "text") ?: return@mapNotNull null
            val ownerArea = block.substringAfter("\"ownerText\":", "")
            val owner = field(ownerArea, "text") ?: "YouTube"
            val image = field(block.substringAfter("\"thumbnail\":", ""), "url")
                ?.replace("\\u0026", "&").orEmpty()
            NativeMediaCard(id, decode(title), decode(owner), image, "https://www.youtube.com/watch?v=$id")
        }.distinctBy { it.id }
    }

    fun bilibiliDynamic(payload: String): List<NativeMediaCard> {
        val root = runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return emptyList()
        val items = root.objectValue("data")?.get("items") as? JsonArray ?: return emptyList()
        return items.mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val modules = item.objectValue("modules") ?: return@mapNotNull null
            val author = modules.objectValue("module_author")
            val archive = modules.objectValue("module_dynamic")?.objectValue("major")?.objectValue("archive")
                ?: return@mapNotNull null
            val bvid = archive.stringValue("bvid") ?: return@mapNotNull null
            val title = archive.stringValue("title") ?: return@mapNotNull null
            val subtitle = listOf(author?.stringValue("name"), author?.stringValue("pub_time"))
                .filterNotNull().filter(String::isNotBlank).joinToString(" · ").ifBlank { "Bilibili 動態" }
            NativeMediaCard(
                id = "dynamic:${item.stringValue("id_str") ?: bvid}",
                title = title,
                subtitle = subtitle,
                thumbnailURL = normalizeImage(archive.stringValue("cover").orEmpty()),
                playbackURL = "https://www.bilibili.com/video/$bvid",
            )
        }.distinctBy(NativeMediaCard::id)
    }

    fun bilibiliProfile(payload: String): List<NativeMediaCard> {
        val root = runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return emptyList()
        val data = root.objectValue("data") ?: return emptyList()
        val name = data.stringValue("uname") ?: return emptyList()
        val level = data.objectValue("level_info")?.numberText("current_level") ?: "?"
        val coins = data.numberText("money") ?: "0"
        val mid = data.numberText("mid") ?: "0"
        return listOf(
            NativeMediaCard(
                id = "profile:$mid",
                title = name,
                subtitle = "LV$level · 硬幣 $coins",
                thumbnailURL = normalizeImage(data.stringValue("face").orEmpty()),
                playbackURL = "https://space.bilibili.com/$mid",
            ),
        )
    }

    private fun field(value: String, name: String): String? =
        Regex("\"${Regex.escape(name)}\"\\s*:\\s*\"([^\"]*)\"").find(value)?.groupValues?.get(1)

    private fun numberField(value: String, name: String): String? =
        Regex("\"${Regex.escape(name)}\"\\s*:\\s*(\\d+)").find(value)?.groupValues?.get(1)

    private fun normalizeImage(value: String): String = when {
        value.startsWith("//") -> "https:$value"
        else -> value
    }

    private fun decode(value: String): String = value
        .replace("\\u0026", "&")
        .replace("\\/", "/")
        .replace("\\\"", "\"")

    private fun clean(value: String): String = decode(value).replace(Regex("<[^>]+>"), "").trim()

    private fun JsonObject.objectValue(key: String): JsonObject? = get(key) as? JsonObject
    private fun JsonObject.stringValue(key: String): String? = get(key)?.jsonPrimitive?.contentOrNull
    private fun JsonObject.numberText(key: String): String? = get(key)?.jsonPrimitive?.contentOrNull
}
