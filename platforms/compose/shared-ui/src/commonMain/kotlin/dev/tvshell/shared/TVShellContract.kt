package dev.tvshell.shared

object TVShellDesign {
    const val ReferenceWidth = 1920f
    const val ReferenceHeight = 1080f
    const val HorizontalPadding = 86f
    const val TopPadding = 48f
    const val CardSpacing = 42f
    const val AppTileWidth = 222f
    const val AppTileAspectRatio = 1.55f
    const val AppTitleSize = 34f
    const val FocusScale = 1.06f
    const val FocusLift = 10f
    const val FocusAnimationMilliseconds = 180
}

enum class RemoteCommand {
    Up, Down, Left, Right, Select, Back, Home, Menu,
    PlayPause, Rewind, FastForward, VolumeUp, VolumeDown, Mute
}

data class ShellApp(
    val id: String,
    val name: String,
    val subtitle: String = "App",
    val packageName: String? = null,
    val executable: String? = null,
    val isSystemSettings: Boolean = false,
)

interface PlatformAdapter {
    fun installedApps(): List<ShellApp>
    fun launch(app: ShellApp): Result<Unit>
    fun openSystemSettings(): Result<Unit>
    fun fetchMediaFeed(service: NativeMediaService): Result<List<NativeMediaCard>> =
        Result.failure(UnsupportedOperationException("此平台尚未連接媒體服務"))
    fun fetchAnimeFeed(source: AnimeSourceKind): Result<List<NativeMediaCard>> = when (source) {
        AnimeSourceKind.YouTube -> fetchMediaFeed(NativeMediaService.YouTube)
        AnimeSourceKind.Bilibili -> fetchMediaFeed(NativeMediaService.Bilibili)
        AnimeSourceKind.AniGamer -> Result.success(
            listOf(
                NativeMediaCard(
                    id = "anigamer-official",
                    title = "動畫瘋",
                    subtitle = "官方網站 · 保留廣告、登入與地區限制",
                    thumbnailURL = "",
                    playbackURL = "https://ani.gamer.com.tw/",
                ),
            ),
        )
        AnimeSourceKind.CSS1 -> Result.failure(IllegalStateException("尚未設定 CSS1 訂閱網址"))
        AnimeSourceKind.AniSubsBT -> Result.failure(IllegalStateException("尚未設定 ani-subs BT 訂閱網址"))
        AnimeSourceKind.Mikan -> Result.failure(IllegalStateException("尚未設定 Mikan RSS"))
        AnimeSourceKind.DMHY -> Result.failure(IllegalStateException("尚未設定動漫花園 RSS"))
    }
    fun playMedia(card: NativeMediaCard): Result<Unit> =
        Result.failure(UnsupportedOperationException("此平台尚未連接播放器"))
    fun fetchWallpaperURL(): Result<String> =
        Result.failure(UnsupportedOperationException("此平台尚未連接 Bing 壁紙"))
    fun exitApp(): Result<Unit> = Result.failure(UnsupportedOperationException("此平台不允許由 App 結束程序"))
}

enum class LauncherFocus { Apps, History }

data class LauncherState(
    val apps: List<ShellApp>,
    val historyCount: Int = 0,
    val focus: LauncherFocus = LauncherFocus.Apps,
    val focusedIndex: Int = 0,
    val focusedHistoryIndex: Int = 0,
    val status: String = "方向鍵選擇 App，OK 開啟，Menu 進入控制中心。",
) {
    val focusedApp: ShellApp? get() = apps.getOrNull(focusedIndex)

    fun reduce(command: RemoteCommand): LauncherState = when (command) {
        RemoteCommand.Left -> when (focus) {
            LauncherFocus.Apps -> copy(focusedIndex = (focusedIndex - 1).coerceAtLeast(0))
            LauncherFocus.History -> copy(focusedHistoryIndex = (focusedHistoryIndex - 1).coerceAtLeast(0))
        }
        RemoteCommand.Right -> when (focus) {
            LauncherFocus.Apps -> copy(focusedIndex = (focusedIndex + 1).coerceAtMost((apps.size - 1).coerceAtLeast(0)))
            LauncherFocus.History -> copy(focusedHistoryIndex = (focusedHistoryIndex + 1).coerceAtMost((historyCount - 1).coerceAtLeast(0)))
        }
        RemoteCommand.Down -> if (focus == LauncherFocus.Apps && historyCount > 0) copy(focus = LauncherFocus.History) else this
        RemoteCommand.Up -> if (focus == LauncherFocus.History) copy(focus = LauncherFocus.Apps) else this
        else -> this
    }
}

data class AnimeState(
    val tabs: List<String> = listOf("推薦", "正版來源", "我的訂閱", "觀看記錄", "搜尋"),
    val focusedTab: Int = 0,
    val focusedCard: Int = 0,
    val isTopNavigationFocused: Boolean = true,
) {
    fun reduce(command: RemoteCommand): AnimeState = when {
        isTopNavigationFocused && command == RemoteCommand.Left -> copy(focusedTab = (focusedTab - 1).coerceAtLeast(0))
        isTopNavigationFocused && command == RemoteCommand.Right -> copy(focusedTab = (focusedTab + 1).coerceAtMost(tabs.lastIndex))
        isTopNavigationFocused && command == RemoteCommand.Down -> copy(isTopNavigationFocused = false)
        isTopNavigationFocused.not() && command == RemoteCommand.Up -> copy(isTopNavigationFocused = true)
        isTopNavigationFocused.not() && command == RemoteCommand.Left -> copy(focusedCard = (focusedCard - 1).coerceAtLeast(0))
        isTopNavigationFocused.not() && command == RemoteCommand.Right -> copy(focusedCard = (focusedCard + 1).coerceAtMost(7))
        else -> this
    }
}
