package dev.tvshell.shared.anime

import dev.tvshell.shared.AnimeSourceKind
import dev.tvshell.shared.NativeMediaCard

data class AnimePlatformCapabilities(
    val css1: Boolean,
    val danmaku: Boolean,
    val internalPlayer: Boolean,
)

interface PlatformAnimeService {
    val capabilities: AnimePlatformCapabilities
    val css1SubscriptionURL: String
    fun feed(source: AnimeSourceKind): Result<List<NativeMediaCard>>
    fun episodes(source: AnimeSourceKind, card: NativeMediaCard): Result<List<AnimeEpisode>>
    fun streams(source: AnimeSourceKind, episode: AnimeEpisode): Result<List<AnimeStreamCandidate>>
    fun load(candidate: AnimeStreamCandidate): Result<Unit>
    fun play(): Result<Unit>
    fun pause(): Result<Unit>
    fun seekBy(seconds: Int): Result<Unit>
    fun volume(direction: Int): Result<Unit> = Result.success(Unit)
    fun stop(): Result<Unit>
    fun danmaku(source: AnimeSourceKind, card: NativeMediaCard, episode: AnimeEpisode): Result<List<DanmakuComment>>
}
