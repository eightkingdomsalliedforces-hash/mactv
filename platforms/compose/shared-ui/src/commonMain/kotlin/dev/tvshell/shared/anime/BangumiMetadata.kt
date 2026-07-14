package dev.tvshell.shared.anime

import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.NativeMediaCard
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

data class BangumiSubjectMetadata(
    val id: Int,
    val name: String,
    val chineseName: String?,
    val summary: String?,
    val episodeCount: Int?,
    val coverURL: String?,
) {
    val title: String get() = chineseName?.takeIf(String::isNotBlank) ?: name
    val aliases: List<String> get() = listOf(title, name).map(String::trim).filter(String::isNotBlank).distinct()

    fun asCard(): NativeMediaCard = NativeMediaCard(
        id = "bangumi-$id",
        title = title,
        subtitle = listOfNotNull(episodeCount?.let { "全 $it 話" }, summary?.take(80)).joinToString(" · ").ifBlank { "Bangumi" },
        thumbnailURL = coverURL.orEmpty(),
        playbackURL = "https://bgm.tv/subject/$id",
        animeSource = AnimeSourceKind.BangumiYouTube,
        alternateTitles = aliases,
        episodeCount = episodeCount,
    )
}

object BangumiMetadataParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun subjects(payload: String): List<BangumiSubjectMetadata> {
        val root = runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull() ?: return emptyList()
        val data = root["data"] as? JsonArray ?: return emptyList()
        return data.mapNotNull(::subject)
    }

    fun calendar(payload: String): List<BangumiSubjectMetadata> {
        val days = runCatching { json.parseToJsonElement(payload) as? JsonArray }.getOrNull() ?: return emptyList()
        return days.flatMap { day ->
            ((day as? JsonObject)?.get("items") as? JsonArray).orEmpty().mapNotNull(::subject)
        }.distinctBy(BangumiSubjectMetadata::id)
    }

    fun subject(payload: String): BangumiSubjectMetadata? =
        runCatching { json.parseToJsonElement(payload) as? JsonObject }.getOrNull()?.let(::subject)

    private fun subject(element: kotlinx.serialization.json.JsonElement): BangumiSubjectMetadata? =
        (element as? JsonObject)?.let(::subject)

    private fun subject(item: JsonObject): BangumiSubjectMetadata? {
        val id = item["id"]?.jsonPrimitive?.intOrNull ?: return null
        val name = item.text("name") ?: return null
        val images = runCatching { item["images"]?.jsonObject }.getOrNull()
        return BangumiSubjectMetadata(
            id = id,
            name = name,
            chineseName = item.text("name_cn"),
            summary = item.text("summary"),
            episodeCount = item["eps"]?.jsonPrimitive?.intOrNull,
            coverURL = listOf("large", "common", "medium", "small", "grid")
                .firstNotNullOfOrNull { images?.text(it) }
                ?.replace("http://", "https://"),
        )
    }

    private fun JsonObject.text(name: String): String? = this[name]?.jsonPrimitive?.contentOrNull?.trim()?.takeIf(String::isNotBlank)
}
