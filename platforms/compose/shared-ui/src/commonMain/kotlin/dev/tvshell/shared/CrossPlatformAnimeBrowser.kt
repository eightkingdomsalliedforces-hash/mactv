package dev.tvshell.shared

enum class CrossPlatformAnimePhase { Sources, Loading, Titles }

enum class AnimeTopTab(val title: String) {
    Recommended("推薦"),
    OfficialSources("正版來源"),
    Subscriptions("我的訂閱"),
    History("觀看記錄"),
    Search("搜尋"),
}

data class CrossPlatformAnimeBrowserState(
    val sourceCount: Int,
    val phase: CrossPlatformAnimePhase = CrossPlatformAnimePhase.Sources,
    val focusedTopTab: AnimeTopTab = AnimeTopTab.Recommended,
    val focusedSource: Int = 0,
    val focusedCard: Int = 0,
    val cardCount: Int = 0,
    val isTopNavigationFocused: Boolean = true,
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): CrossPlatformAnimeBrowserState = when (phase) {
        CrossPlatformAnimePhase.Sources -> when {
            command == RemoteCommand.Back || command == RemoteCommand.Home -> copy(pendingAction = "exit")
            isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedTopTab = AnimeTopTab.entries[(focusedTopTab.ordinal - 1).coerceAtLeast(0)])
            isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedTopTab = AnimeTopTab.entries[(focusedTopTab.ordinal + 1).coerceAtMost(AnimeTopTab.entries.lastIndex)])
            isTopNavigationFocused && command == RemoteCommand.Down -> copy(isTopNavigationFocused = false)
            !isTopNavigationFocused && command == RemoteCommand.Up -> copy(isTopNavigationFocused = true)
            !isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedSource = (focusedSource - 1).coerceAtLeast(0))
            !isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedSource = (focusedSource + 1).coerceAtMost((sourceCount - 1).coerceAtLeast(0)))
            !isTopNavigationFocused && command == RemoteCommand.Select -> copy(phase = CrossPlatformAnimePhase.Loading, pendingAction = "load:$focusedSource")
            else -> this
        }
        CrossPlatformAnimePhase.Loading -> when (command) {
            RemoteCommand.Back, RemoteCommand.Home -> backToSources()
            else -> this
        }
        CrossPlatformAnimePhase.Titles -> when (command) {
            RemoteCommand.Left -> copy(focusedCard = (focusedCard - 1).coerceAtLeast(0))
            RemoteCommand.Right -> copy(focusedCard = (focusedCard + 1).coerceAtMost((cardCount - 1).coerceAtLeast(0)))
            RemoteCommand.Select -> copy(pendingAction = "play:$focusedCard")
            RemoteCommand.Back -> backToSources()
            else -> this
        }
    }

    fun loaded(cardCount: Int) = copy(
        phase = CrossPlatformAnimePhase.Titles,
        focusedCard = 0,
        cardCount = cardCount,
        pendingAction = null,
        isTopNavigationFocused = false,
    )

    fun failed() = backToSources()
    fun clearAction() = copy(pendingAction = null)
    fun backToSources() = copy(phase = CrossPlatformAnimePhase.Sources, cardCount = 0, focusedCard = 0, pendingAction = null)
}
