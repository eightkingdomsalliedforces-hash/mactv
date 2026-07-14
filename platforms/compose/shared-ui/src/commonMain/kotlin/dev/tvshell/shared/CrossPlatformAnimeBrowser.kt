package dev.tvshell.shared

import dev.tvshell.shared.anime.AnimeStreamCandidate

enum class CrossPlatformAnimePhase {
    Sources,
    Loading,
    Titles,
    Details,
    EpisodeLoading,
    Episodes,
    Resolving,
    Playing,
}

enum class AnimeTopTab(val title: String) {
    Recommended("推薦"),
    OfficialSources("正版來源"),
    Subscriptions("我的訂閱"),
    History("觀看記錄"),
    Search("搜尋"),
}

enum class AnimeSourceKind {
    Bilibili,
    BangumiYouTube,
    AniGamer,
    YouTube,
    CSS1,
    AniSubsBT,
    Mikan,
    DMHY,
}

data class AnimeSourceDefinition(
    val kind: AnimeSourceKind,
    val title: String,
    val subtitle: String,
    val tab: AnimeTopTab,
)

private val defaultAnimeSources = listOf(
    AnimeSourceDefinition(AnimeSourceKind.Bilibili, "Bilibili 番劇", "推薦、排行與搜尋", AnimeTopTab.Recommended),
    AnimeSourceDefinition(AnimeSourceKind.BangumiYouTube, "Bangumi + YouTube", "Bangumi 資料與別名 · YouTube 播放", AnimeTopTab.Recommended),
    AnimeSourceDefinition(AnimeSourceKind.YouTube, "官方 YouTube 動畫", "正版授權頻道", AnimeTopTab.Recommended),
    AnimeSourceDefinition(AnimeSourceKind.AniGamer, "動畫瘋", "官方網站 · 保留廣告與限制", AnimeTopTab.OfficialSources),
    AnimeSourceDefinition(AnimeSourceKind.YouTube, "官方 YouTube", "正版授權頻道", AnimeTopTab.OfficialSources),
    AnimeSourceDefinition(AnimeSourceKind.CSS1, "ani-subs CSS1", "Web Selector 訂閱", AnimeTopTab.Subscriptions),
    AnimeSourceDefinition(AnimeSourceKind.AniSubsBT, "ani-subs BT", "RSS／BT 訂閱", AnimeTopTab.Subscriptions),
    AnimeSourceDefinition(AnimeSourceKind.Mikan, "Mikan Project", "RSS／BT", AnimeTopTab.Subscriptions),
    AnimeSourceDefinition(AnimeSourceKind.DMHY, "動漫花園", "RSS／BT", AnimeTopTab.Subscriptions),
)

fun animeSourcesFor(tab: AnimeTopTab): List<AnimeSourceDefinition> =
    defaultAnimeSources.filter { it.tab == tab }

data class CrossPlatformAnimeBrowserState(
    val sourceCount: Int = animeSourcesFor(AnimeTopTab.Recommended).size,
    val gridColumns: Int = 4,
    val phase: CrossPlatformAnimePhase = CrossPlatformAnimePhase.Sources,
    val focusedTopTab: AnimeTopTab = AnimeTopTab.Recommended,
    val focusedSource: Int = 0,
    val focusedCard: Int = 0,
    val cardCount: Int = 0,
    val selectedCardIndex: Int = 0,
    val episodeCount: Int = 0,
    val focusedEpisode: Int = 0,
    val streamCandidates: List<AnimeStreamCandidate> = emptyList(),
    val focusedStreamIndex: Int = 0,
    val selectedStreamIndex: Int = 0,
    val isStreamPickerVisible: Boolean = false,
    val isPlaying: Boolean = true,
    val isPlayerHUDVisible: Boolean = true,
    val pendingSeekSeconds: Int = 0,
    val isTopNavigationFocused: Boolean = true,
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): CrossPlatformAnimeBrowserState {
        if (isStreamPickerVisible) {
            return when (command) {
                RemoteCommand.Left, RemoteCommand.Up -> copy(
                    focusedStreamIndex = (focusedStreamIndex - 1).coerceAtLeast(0),
                    pendingAction = null,
                )
                RemoteCommand.Right, RemoteCommand.Down -> copy(
                    focusedStreamIndex = (focusedStreamIndex + 1).coerceAtMost((streamCandidates.size - 1).coerceAtLeast(0)),
                    pendingAction = null,
                )
                RemoteCommand.Select -> streamCandidates.getOrNull(focusedStreamIndex)?.let { candidate ->
                    copy(
                        phase = CrossPlatformAnimePhase.Playing,
                        selectedStreamIndex = focusedStreamIndex,
                        isStreamPickerVisible = false,
                        isPlaying = true,
                        isPlayerHUDVisible = true,
                        pendingAction = "load:${candidate.url}",
                    )
                } ?: this
                RemoteCommand.Back, RemoteCommand.Home -> copy(
                    phase = CrossPlatformAnimePhase.Episodes,
                    isStreamPickerVisible = false,
                    pendingAction = "stop",
                )
                RemoteCommand.Menu -> copy(isStreamPickerVisible = false, pendingAction = null)
                else -> this
            }
        }
        return when (phase) {
        CrossPlatformAnimePhase.Sources -> when {
            command == RemoteCommand.Back || command == RemoteCommand.Home -> copy(pendingAction = "exit")
            isTopNavigationFocused && command == RemoteCommand.Left -> selectingTopTab(focusedTopTab.ordinal - 1)
            isTopNavigationFocused && command == RemoteCommand.Right -> selectingTopTab(focusedTopTab.ordinal + 1)
            isTopNavigationFocused && command == RemoteCommand.Down -> copy(isTopNavigationFocused = false)
            !isTopNavigationFocused && command == RemoteCommand.Up -> copy(isTopNavigationFocused = true)
            !isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedSource = (focusedSource - 1).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedSource = (focusedSource + 1).coerceAtMost((sourceCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Select && sourceCount > 0 -> copy(phase = CrossPlatformAnimePhase.Loading, pendingAction = "load:$focusedSource")
            else -> this
        }
        CrossPlatformAnimePhase.Loading -> when (command) {
            RemoteCommand.Back, RemoteCommand.Home -> backToSources()
            else -> this
        }
        CrossPlatformAnimePhase.Titles -> when {
            isTopNavigationFocused && command == RemoteCommand.Left -> selectingTopTab(focusedTopTab.ordinal - 1)
            isTopNavigationFocused && command == RemoteCommand.Right -> selectingTopTab(focusedTopTab.ordinal + 1)
            isTopNavigationFocused && command == RemoteCommand.Down && cardCount > 0 -> copy(isTopNavigationFocused = false)
            !isTopNavigationFocused && command == RemoteCommand.Up && focusedCard < gridColumns -> copy(isTopNavigationFocused = true)
            !isTopNavigationFocused && command == RemoteCommand.Up -> copy(focusedCard = (focusedCard - gridColumns).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Down -> copy(focusedCard = (focusedCard + gridColumns).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedCard = (focusedCard - 1).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedCard = (focusedCard + 1).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Select && cardCount > 0 -> copy(
                phase = CrossPlatformAnimePhase.Details,
                selectedCardIndex = focusedCard,
                pendingAction = null,
            )
            command == RemoteCommand.Back -> backToSources()
            else -> this
        }
        CrossPlatformAnimePhase.Details -> when (command) {
            RemoteCommand.Select -> copy(
                phase = CrossPlatformAnimePhase.EpisodeLoading,
                pendingAction = "episodes:$selectedCardIndex",
            )
            RemoteCommand.Back -> copy(
                phase = CrossPlatformAnimePhase.Titles,
                focusedCard = selectedCardIndex,
                isTopNavigationFocused = false,
                pendingAction = null,
            )
            else -> this
        }
        CrossPlatformAnimePhase.EpisodeLoading -> when (command) {
            RemoteCommand.Back, RemoteCommand.Home -> copy(phase = CrossPlatformAnimePhase.Details, pendingAction = null)
            else -> this
        }
        CrossPlatformAnimePhase.Episodes -> when (command) {
            RemoteCommand.Left -> copy(focusedEpisode = (focusedEpisode - 1).coerceAtLeast(0))
            RemoteCommand.Right -> copy(focusedEpisode = (focusedEpisode + 1).coerceAtMost((episodeCount - 1).coerceAtLeast(0)))
            RemoteCommand.Up -> copy(focusedEpisode = (focusedEpisode - gridColumns).coerceAtLeast(0))
            RemoteCommand.Down -> copy(focusedEpisode = (focusedEpisode + gridColumns).coerceAtMost((episodeCount - 1).coerceAtLeast(0)))
            RemoteCommand.Select -> if (episodeCount > 0) copy(
                phase = CrossPlatformAnimePhase.Resolving,
                pendingAction = "streams:$focusedEpisode",
            ) else this
            RemoteCommand.Back -> copy(phase = CrossPlatformAnimePhase.Details, pendingAction = null)
            else -> this
        }
        CrossPlatformAnimePhase.Resolving -> when (command) {
            RemoteCommand.Back, RemoteCommand.Home -> copy(
                phase = CrossPlatformAnimePhase.Episodes,
                isStreamPickerVisible = false,
                pendingAction = null,
            )
            else -> this
        }
        CrossPlatformAnimePhase.Playing -> when (command) {
            RemoteCommand.Select, RemoteCommand.PlayPause -> copy(
                isPlaying = !isPlaying,
                isPlayerHUDVisible = true,
                pendingAction = if (isPlaying) "pause" else "play",
            )
            RemoteCommand.Left, RemoteCommand.Rewind -> copy(
                pendingSeekSeconds = -15,
                isPlayerHUDVisible = true,
                pendingAction = "seek:-15",
            )
            RemoteCommand.Right, RemoteCommand.FastForward -> copy(
                pendingSeekSeconds = 15,
                isPlayerHUDVisible = true,
                pendingAction = "seek:15",
            )
            RemoteCommand.Up, RemoteCommand.VolumeUp -> copy(isPlayerHUDVisible = true, pendingAction = "volume:up")
            RemoteCommand.Down, RemoteCommand.VolumeDown -> copy(isPlayerHUDVisible = true, pendingAction = "volume:down")
            RemoteCommand.Mute -> copy(isPlayerHUDVisible = true, pendingAction = "volume:mute")
            RemoteCommand.Menu -> if (streamCandidates.size > 1) copy(
                isStreamPickerVisible = true,
                focusedStreamIndex = selectedStreamIndex,
                isPlayerHUDVisible = true,
                pendingAction = null,
            ) else copy(isPlayerHUDVisible = true, pendingAction = null)
            RemoteCommand.Back, RemoteCommand.Home -> copy(
                phase = CrossPlatformAnimePhase.Episodes,
                isPlaying = false,
                isPlayerHUDVisible = false,
                pendingAction = "stop",
            )
        }
    }
    }

    fun loaded(cardCount: Int) = copy(
        phase = CrossPlatformAnimePhase.Titles,
        focusedCard = 0,
        cardCount = cardCount,
        pendingAction = null,
        isTopNavigationFocused = true,
    )

    fun loadingFirstSource() = copy(
        focusedTopTab = AnimeTopTab.Recommended,
        sourceCount = animeSourcesFor(AnimeTopTab.Recommended).size,
        focusedSource = 0,
        phase = CrossPlatformAnimePhase.Loading,
        pendingAction = "load:0",
        isTopNavigationFocused = true,
    )

    fun failed() = backToSources()
    fun clearAction() = copy(pendingAction = null, pendingSeekSeconds = 0)

    fun episodesLoaded(episodeCount: Int) = copy(
        phase = if (episodeCount > 0) CrossPlatformAnimePhase.Episodes else CrossPlatformAnimePhase.Details,
        episodeCount = episodeCount,
        focusedEpisode = 0,
        pendingAction = null,
    )

    fun streamsLoaded(candidates: List<AnimeStreamCandidate>): CrossPlatformAnimeBrowserState {
        val choices = candidates.distinctBy { it.url }
        return when (choices.size) {
            0 -> copy(phase = CrossPlatformAnimePhase.Episodes, streamCandidates = emptyList(), pendingAction = null)
            1 -> copy(
                phase = CrossPlatformAnimePhase.Playing,
                streamCandidates = choices,
                selectedStreamIndex = 0,
                focusedStreamIndex = 0,
                isStreamPickerVisible = false,
                isPlaying = true,
                isPlayerHUDVisible = true,
                pendingAction = "load:${choices.first().url}",
            )
            else -> copy(
                phase = CrossPlatformAnimePhase.Resolving,
                streamCandidates = choices,
                selectedStreamIndex = 0,
                focusedStreamIndex = 0,
                isStreamPickerVisible = true,
                pendingAction = null,
            )
        }
    }

    fun hidePlayerHUD() = if (phase == CrossPlatformAnimePhase.Playing) copy(isPlayerHUDVisible = false) else this

    fun backToSources() = copy(
        phase = CrossPlatformAnimePhase.Sources,
        cardCount = 0,
        focusedCard = 0,
        selectedCardIndex = 0,
        episodeCount = 0,
        focusedEpisode = 0,
        streamCandidates = emptyList(),
        isStreamPickerVisible = false,
        pendingAction = null,
    )

    private fun selectingTopTab(index: Int): CrossPlatformAnimeBrowserState {
        val tab = AnimeTopTab.entries[index.coerceIn(AnimeTopTab.entries.indices)]
        return copy(
            focusedTopTab = tab,
            sourceCount = animeSourcesFor(tab).size,
            phase = CrossPlatformAnimePhase.Sources,
            focusedSource = 0,
            focusedCard = 0,
            cardCount = 0,
            pendingAction = null,
        )
    }
}
