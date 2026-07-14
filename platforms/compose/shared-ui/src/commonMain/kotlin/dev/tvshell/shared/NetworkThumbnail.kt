package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

data class NetworkThumbnailRequest(val url: String) {
    val isLoadable: Boolean get() = url.startsWith("https://") || url.startsWith("http://")
}

@Composable
expect fun NetworkThumbnail(
    request: NetworkThumbnailRequest,
    contentDescription: String,
    modifier: Modifier = Modifier,
)
