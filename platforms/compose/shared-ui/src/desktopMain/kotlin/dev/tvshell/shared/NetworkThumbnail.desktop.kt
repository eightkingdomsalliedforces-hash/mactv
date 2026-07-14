package dev.tvshell.shared

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.skia.Image

@Composable
actual fun NetworkThumbnail(
    request: NetworkThumbnailRequest,
    contentDescription: String,
    modifier: Modifier,
) {
    var bitmap by remember(request.url) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(request.url) {
        bitmap = if (request.isLoadable) withContext(Dispatchers.IO) { loadDesktopThumbnail(request.url) } else null
    }
    val image = bitmap
    if (image == null) Box(modifier) else Image(
        bitmap = image,
        contentDescription = contentDescription,
        contentScale = ContentScale.Crop,
        modifier = modifier,
    )
}

private fun loadDesktopThumbnail(url: String): ImageBitmap? = runCatching {
    val connection = URI(url).toURL().openConnection() as HttpURLConnection
    connection.connectTimeout = 8_000
    connection.readTimeout = 8_000
    connection.setRequestProperty("User-Agent", "Mozilla/5.0 TVShell/1.0")
    try {
        require(connection.responseCode in 200..299)
        Image.makeFromEncoded(connection.inputStream.use { it.readBytes() }).toComposeImageBitmap()
    } finally {
        connection.disconnect()
    }
}.getOrNull()
