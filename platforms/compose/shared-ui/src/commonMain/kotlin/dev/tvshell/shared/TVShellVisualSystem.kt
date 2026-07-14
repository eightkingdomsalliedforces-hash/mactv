package dev.tvshell.shared

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

object TVShellVisual {
    const val CornerRadius = 28f
    const val DockInset = 34f
    const val AppIconCornerRadius = 18f
    const val FocusAnimationMilliseconds = TVShellDesign.FocusAnimationMilliseconds
    const val FocusDampingRatio = .80f
    const val RuntimeAnimationMilliseconds = 380
    val BackdropTop = Color(0xFF23252C)
    val BackdropBottom = Color(0xFF090A0D)
    val Surface = Color(0xCC24262D)
    val ContentSurface = Color(0xB82D3038)
    val FocusSurface = Color(0xFFF0F1F3)
}

internal fun referenceCanvasScale(width: Float, height: Float): Float = minOf(
    width / 1920f,
    height / 1080f,
).coerceAtLeast(.1f)

enum class TVSurfaceRole { Dock, Panel, Content, Alert }

@Composable
fun TVShellBackdrop(wallpaperURL: String? = null, content: @Composable BoxScope.() -> Unit) {
    androidx.compose.foundation.layout.Box(
        Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(TVShellVisual.BackdropTop, TVShellVisual.BackdropBottom))),
    ) {
        if (wallpaperURL != null) {
            NetworkThumbnail(NetworkThumbnailRequest(wallpaperURL), "Bing 每日圖片", Modifier.fillMaxSize())
            androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .28f)))
        }
        content()
    }
}

@Composable
fun Modifier.tvShellFocus(isFocused: Boolean): Modifier {
    val scale by animateFloatAsState(
        targetValue = if (isFocused) TVShellDesign.FocusScale else 1f,
        animationSpec = spring(dampingRatio = TVShellVisual.FocusDampingRatio, stiffness = 420f),
        label = "TVShell focus scale",
    )
    val lift by animateFloatAsState(
        targetValue = if (isFocused) -TVShellDesign.FocusLift else 0f,
        animationSpec = spring(dampingRatio = TVShellVisual.FocusDampingRatio, stiffness = 420f),
        label = "TVShell focus lift",
    )
    return graphicsLayer {
        scaleX = scale
        scaleY = scale
        translationY = lift
    }
}

fun Modifier.tvShellSurface(
    role: TVSurfaceRole,
    isFocused: Boolean = false,
    cornerRadius: Float = TVShellVisual.CornerRadius,
): Modifier {
    val shape = RoundedCornerShape(cornerRadius.dp)
    val color = when {
        isFocused -> TVShellVisual.FocusSurface
        role == TVSurfaceRole.Content -> TVShellVisual.ContentSurface
        else -> TVShellVisual.Surface
    }
    return clip(shape)
        .background(color)
        .border(1.dp, Color.White.copy(alpha = if (isFocused) .46f else .12f), shape)
        .shadow(if (isFocused) 20.dp else 8.dp, shape, clip = false)
}
