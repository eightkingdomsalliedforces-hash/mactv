package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

data class NetworkThumbnailRequest(val url: String) {
    val isLoadable: Boolean get() = url.startsWith("https://") || url.startsWith("http://")
    val headers: Map<String, String> get() = if (url.contains("hdslb.com")) {
        mapOf("Referer" to "https://www.bilibili.com/")
    } else {
        emptyMap()
    }
}

object BingWallpaperMetadata {
    fun imageURL(payload: String): String? {
        val value = Regex("\\\"url\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"")
            .find(payload)?.groupValues?.getOrNull(1)
            ?.replace("\\u0026", "&")
            ?.replace("\\/", "/")
            ?: return null
        return when {
            value.startsWith("https://") || value.startsWith("http://") -> value
            value.startsWith("/") -> "https://www.bing.com$value"
            else -> null
        }
    }
}

expect fun currentTVShellTimeLabel(): String

@Composable
expect fun NetworkThumbnail(
    request: NetworkThumbnailRequest,
    contentDescription: String,
    modifier: Modifier = Modifier,
)
