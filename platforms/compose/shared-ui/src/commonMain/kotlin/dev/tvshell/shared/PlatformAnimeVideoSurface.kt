package dev.tvshell.shared

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import dev.tvshell.shared.anime.AnimeStreamCandidate

@Composable
expect fun PlatformAnimeVideoSurface(
    candidate: AnimeStreamCandidate?,
    signal: WebRuntimeSignal,
    onExitRequested: () -> Unit,
    modifier: Modifier = Modifier,
)
