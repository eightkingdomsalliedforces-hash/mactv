package dev.tvshell.shared

import dev.tvshell.shared.anime.DefaultCSS1SubscriptionURL
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.floatOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class AnimeSourceSettings(
    val css1SubscriptionURL: String = DefaultCSS1SubscriptionURL,
    val css1Enabled: Boolean = true,
) {
    fun withCSS1URL(value: String): AnimeSourceSettings {
        val normalized = value.trim()
        require(normalized.startsWith("https://") || normalized.startsWith("http://")) {
            "CSS1 訂閱網址必須使用 http 或 https"
        }
        return copy(css1SubscriptionURL = normalized)
    }

    fun resetCSS1(): AnimeSourceSettings = AnimeSourceSettings()
}

data class ShellPreferences(
    val animeSources: AnimeSourceSettings = AnimeSourceSettings(),
    val history: WatchHistoryState = WatchHistoryState(),
    val controlCenter: ControlCenterState = ControlCenterState(),
)

object ShellPreferencesCodec {
    private val json = Json { ignoreUnknownKeys = true }

    fun encode(value: ShellPreferences): String = buildJsonObject {
        put("version", 1)
        put("animeSources", buildJsonObject {
            put("css1SubscriptionURL", value.animeSources.css1SubscriptionURL)
            put("css1Enabled", value.animeSources.css1Enabled)
        })
        put("history", buildJsonArray {
            value.history.entries.forEach { card ->
                add(buildJsonObject {
                    put("id", card.id)
                    put("title", card.title)
                    put("subtitle", card.subtitle)
                    put("thumbnailURL", card.thumbnailURL)
                    put("playbackURL", card.playbackURL)
                    card.animeSource?.let { put("animeSource", it.name) }
                    if (card.alternateTitles.isNotEmpty()) put("alternateTitles", buildJsonArray {
                        card.alternateTitles.forEach { add(JsonPrimitive(it)) }
                    })
                    card.episodeCount?.let { put("episodeCount", it) }
                })
            }
        })
        put("controlCenter", buildJsonObject {
            put("displayScaleIndex", value.controlCenter.displayScaleIndex)
            put("wallpaperIndex", value.controlCenter.wallpaperIndex)
            put("webZoom", value.controlCenter.webZoom)
            put("volume", value.controlCenter.volume)
            put("isMuted", value.controlCenter.isMuted)
            put("danmaku", buildJsonObject {
                put("sizeScale", value.controlCenter.danmaku.sizeScale)
                put("speedScale", value.controlCenter.danmaku.speedScale)
                put("opacity", value.controlCenter.danmaku.opacity)
                put("density", value.controlCenter.danmaku.density)
                put("isVisible", value.controlCenter.danmaku.isVisible)
            })
        })
    }.toString()

    fun decode(payload: String): ShellPreferences {
        val root = json.parseToJsonElement(payload) as? JsonObject ?: return ShellPreferences()
        val sourceObject = root["animeSources"] as? JsonObject
        val animeSources = AnimeSourceSettings(
            css1SubscriptionURL = sourceObject.string("css1SubscriptionURL") ?: DefaultCSS1SubscriptionURL,
            css1Enabled = sourceObject.boolean("css1Enabled") ?: true,
        )
        val history = (root["history"] as? JsonArray).orEmpty().mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val id = item.string("id") ?: return@mapNotNull null
            val title = item.string("title") ?: return@mapNotNull null
            val playbackURL = item.string("playbackURL") ?: return@mapNotNull null
            NativeMediaCard(
                id = id,
                title = title,
                subtitle = item.string("subtitle").orEmpty(),
                thumbnailURL = item.string("thumbnailURL").orEmpty(),
                playbackURL = playbackURL,
                animeSource = item.string("animeSource")?.let { runCatching { AnimeSourceKind.valueOf(it) }.getOrNull() },
                alternateTitles = (item["alternateTitles"] as? JsonArray).orEmpty().mapNotNull { it.jsonPrimitive.contentOrNull },
                episodeCount = item.int("episodeCount"),
            )
        }
        val controls = root["controlCenter"] as? JsonObject
        val danmaku = controls?.get("danmaku") as? JsonObject
        return ShellPreferences(
            animeSources = animeSources,
            history = WatchHistoryState(history.take(8)),
            controlCenter = ControlCenterState(
                displayScaleIndex = controls.int("displayScaleIndex")?.coerceIn(0, 4) ?: 0,
                wallpaperIndex = controls.int("wallpaperIndex")?.coerceIn(0, 3) ?: 0,
                webZoom = controls.float("webZoom")?.coerceIn(.8f, 2.4f) ?: 1.25f,
                volume = controls.float("volume")?.coerceIn(0f, 1f) ?: .70f,
                isMuted = controls.boolean("isMuted") ?: false,
                danmaku = DanmakuSettings(
                    sizeScale = danmaku.float("sizeScale")?.coerceIn(.7f, 1.8f) ?: 1f,
                    speedScale = danmaku.float("speedScale")?.coerceIn(.6f, 1.8f) ?: 1f,
                    opacity = danmaku.float("opacity")?.coerceIn(.35f, 1f) ?: .92f,
                    density = danmaku.int("density")?.coerceIn(1, 10) ?: 5,
                    isVisible = danmaku.boolean("isVisible") ?: true,
                ),
            ),
        )
    }

    private fun JsonObject?.string(key: String): String? = this?.get(key)?.jsonPrimitive?.contentOrNull
    private fun JsonObject?.int(key: String): Int? = this?.get(key)?.jsonPrimitive?.intOrNull
    private fun JsonObject?.float(key: String): Float? = this?.get(key)?.jsonPrimitive?.floatOrNull
    private fun JsonObject?.boolean(key: String): Boolean? = this?.get(key)?.jsonPrimitive?.booleanOrNull
}
