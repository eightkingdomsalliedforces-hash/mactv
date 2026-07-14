package dev.tvshell.shared

enum class CrossPlatformAnimePhase { Sources, Loading, Titles }

enum class AnimeTopTab(val title: String) {
    Recommended("推薦"),
    OfficialSources("正版來源"),
    Subscriptions("我的訂閱"),
    History("觀看記錄"),
    Search("搜尋"),
}

enum class AnimeSourceKind {
    Bilibili,
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
    val isTopNavigationFocused: Boolean = true,
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): CrossPlatformAnimeBrowserState = when (phase) {
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
            !isTopNavigationFocused && command == RemoteCommand.Select -> copy(pendingAction = "play:$focusedCard")
            command == RemoteCommand.Back -> backToSources()
            else -> this
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
    fun clearAction() = copy(pendingAction = null)
    fun backToSources() = copy(phase = CrossPlatformAnimePhase.Sources, cardCount = 0, focusedCard = 0, pendingAction = null)

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
