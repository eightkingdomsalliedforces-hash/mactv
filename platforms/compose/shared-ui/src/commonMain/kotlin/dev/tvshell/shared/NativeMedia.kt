package dev.tvshell.shared

enum class NativeMediaService { YouTube, Bilibili }

data class NativeMediaCard(
    val id: String,
    val title: String,
    val subtitle: String,
    val thumbnailURL: String,
    val playbackURL: String,
)

data class WatchHistoryState(
    val entries: List<NativeMediaCard> = emptyList(),
) {
    fun record(card: NativeMediaCard): WatchHistoryState = copy(
        entries = (listOf(card) + entries.filter { it.id != card.id }).take(8),
    )
}

enum class NativeMediaPhase { Browser, Player }

data class NativeMediaState(
    val cardCount: Int,
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
            isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedTab = (focusedTab + 1).coerceAtMost(3))
            isTopNavigationFocused && command == RemoteCommand.Down && cardCount > 0 -> copy(isTopNavigationFocused = false)
            !isTopNavigationFocused && command == RemoteCommand.Up && focusedCard < gridColumns -> copy(isTopNavigationFocused = true)
            !isTopNavigationFocused && command == RemoteCommand.Up -> copy(focusedCard = (focusedCard - gridColumns).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Down -> copy(focusedCard = (focusedCard + gridColumns).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedCard = (focusedCard - 1).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedCard = (focusedCard + 1).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Select -> copy(phase = NativeMediaPhase.Player, pendingAction = "play:$focusedCard", pendingSeekSeconds = 0, isPlaying = true)
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
}
