package dev.tvshell.shared

import androidx.compose.ui.input.key.Key
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LauncherStateTest {
    @Test
    fun rootDoesNotDispatchASecondCopyWhenWindowOwnsRemoteInput() {
        assertFalse(shouldHandleRootKeyEvent(hasExternalDispatcher = true))
        assertTrue(shouldHandleRootKeyEvent(hasExternalDispatcher = false))
    }
    private val apps = listOf(ShellApp("a", "A"), ShellApp("b", "B"), ShellApp("c", "C"))

    @Test
    fun focusMovesAndClampsInVisualOrder() {
        var state = LauncherState(apps)
        state = state.reduce(RemoteCommand.Left)
        assertEquals(0, state.focusedIndex)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Right).reduce(RemoteCommand.Right)
        assertEquals(2, state.focusedIndex)
        state = state.reduce(RemoteCommand.Left)
        assertEquals("B", state.focusedApp?.name)
    }

    @Test
    fun launcherMovesBetweenDockAndRecentHistoryLikeMacTvshell() {
        var state = LauncherState(apps, historyCount = 2)
        state = state.reduce(RemoteCommand.Down)
        assertEquals(LauncherFocus.History, state.focus)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Right).reduce(RemoteCommand.Right)
        assertEquals(1, state.focusedHistoryIndex)
        state = state.reduce(RemoteCommand.Up)
        assertEquals(LauncherFocus.Apps, state.focus)
    }

    @Test
    fun designTokensMatchCanonicalMacLayout() {
        assertEquals(222f, TVShellDesign.AppTileWidth)
        assertEquals(1.55f, TVShellDesign.AppTileAspectRatio)
        assertEquals(86f, TVShellDesign.HorizontalPadding)
        assertEquals(28f, TVShellVisual.CornerRadius)
        assertEquals(180, TVShellVisual.FocusAnimationMilliseconds)
        assertEquals(.80f, TVShellVisual.FocusDampingRatio)
        assertEquals(380, TVShellVisual.RuntimeAnimationMilliseconds)
        assertEquals(34f, TVShellVisual.DockInset)
        assertEquals(18f, TVShellVisual.AppIconCornerRadius)
    }

    @Test
    fun animeTopNavigationAndCardsClampAtTheirEdges() {
        var state = AnimeState()
        state = state.reduce(RemoteCommand.Left)
        assertEquals(0, state.focusedTab)
        state = state.reduce(RemoteCommand.Right).reduce(RemoteCommand.Right)
        assertEquals(2, state.focusedTab)
        state = state.reduce(RemoteCommand.Down).reduce(RemoteCommand.Right)
        assertEquals(false, state.isTopNavigationFocused)
        assertEquals(1, state.focusedCard)
    }

    @Test
    fun externalDispatcherDeliversOkAndBackToTheActiveScreen() {
        val dispatcher = RemoteCommandDispatcher()
        val received = mutableListOf<RemoteCommand>()
        val unsubscribe = dispatcher.subscribe { received += it }
        dispatcher.dispatch(RemoteCommand.Select)
        dispatcher.dispatch(RemoteCommand.Back)
        unsubscribe()
        dispatcher.dispatch(RemoteCommand.Home)
        assertEquals(listOf(RemoteCommand.Select, RemoteCommand.Back), received)
    }

    @Test
    fun androidTvKeyCodesMapBeforeComposeFocusHandling() {
        assertEquals(RemoteCommand.Select, AndroidTVKeyMapper.command(23, isLongPress = false))
        assertEquals(RemoteCommand.Select, AndroidTVKeyMapper.command(66, isLongPress = false))
        assertEquals(RemoteCommand.Back, AndroidTVKeyMapper.command(4, isLongPress = false))
        assertEquals(RemoteCommand.Home, AndroidTVKeyMapper.command(4, isLongPress = true))
        assertEquals(RemoteCommand.Menu, AndroidTVKeyMapper.command(82, isLongPress = false))
    }

    @Test
    fun windowsMenuSupportsApplicationKeyAndF10() {
        assertEquals(RemoteCommand.Menu, desktopKeyToRemoteCommand(Key.Menu, isShiftPressed = false))
        assertEquals(RemoteCommand.Menu, desktopKeyToRemoteCommand(Key.F10, isShiftPressed = false))
        assertEquals(RemoteCommand.Menu, desktopKeyToRemoteCommand(Key.F10, isShiftPressed = true))
    }

    @Test
    fun controlCenterMatchesMacFocusAndImmediateAdjustments() {
        var state = ControlCenterState()
        state = state.reduce(RemoteCommand.Down)
        assertEquals(ControlCenterItem.Audio, state.focusedItem)
        state = state.reduce(RemoteCommand.Right)
        assertEquals(0.75f, state.volume)
        state = state.reduce(RemoteCommand.Select)
        assertEquals(true, state.isMuted)

        state = state.copy(focusedItem = ControlCenterItem.DanmakuOpacity)
        state = state.reduce(RemoteCommand.Left)
        assertEquals(0.82f, state.danmaku.opacity)
        state = state.reduce(RemoteCommand.Menu)
        assertEquals("close", state.pendingAction)
    }

    @Test
    fun controlCenterClampsDanmakuLikeMacSettings() {
        var state = ControlCenterState(
            focusedItem = ControlCenterItem.DanmakuDensity,
            danmaku = DanmakuSettings(density = 1),
        )
        state = state.reduce(RemoteCommand.Left)
        assertEquals(1, state.danmaku.density)
        state = state.copy(focusedItem = ControlCenterItem.DanmakuVisibility)
            .reduce(RemoteCommand.Select)
        assertFalse(state.danmaku.isVisible)
    }

    @Test
    fun settingsUsesMacRowOrderAndSharedPreferences() {
        var state = SettingsState()
        state = state.reduce(RemoteCommand.Down)
        assertEquals(SettingsItem.Wallpaper, state.focusedItem)
        state = state.reduce(RemoteCommand.Right)
        assertEquals("暮色", state.preferences.wallpaperLabel)
        state = state.copy(focusedItem = SettingsItem.DanmakuOpacity)
            .reduce(RemoteCommand.Left)
        assertEquals(0.82f, state.preferences.danmaku.opacity)
        state = state.reduce(RemoteCommand.Back)
        assertEquals("exit", state.pendingAction)
    }

    @Test
    fun bingWallpaperMetadataResolvesTheFullImageURL() {
        val payload = """{"images":[{"url":"/th?id=OHR.TVShellTest_1920x1080.jpg"}]}"""
        assertEquals(
            "https://www.bing.com/th?id=OHR.TVShellTest_1920x1080.jpg",
            BingWallpaperMetadata.imageURL(payload),
        )
    }

    @Test
    fun launcherShipsTheSameCoreAppsAsNativeMacOS() {
        assertEquals(
            listOf("YouTube", "Bilibili", "Apple", "瀏覽器", "影片", "動畫", "動漫來源", "遙控器", "設定", "管理"),
            defaultShellApps(animeOnly = false).map(ShellApp::name),
        )
        assertEquals(listOf("動畫"), defaultShellApps(animeOnly = true).map(ShellApp::name))
    }

    @Test
    fun everyBuiltInAppOpensItsOwnMacEquivalentRoute() {
        val expected: Map<String, ShellRoute?> = mapOf(
            "youtube" to ShellRoute.YouTube,
            "bilibili" to ShellRoute.Bilibili,
            "apple" to ShellRoute.Browser("https://www.apple.com"),
            "browser" to ShellRoute.Browser("https://duckduckgo.com"),
            "video" to ShellRoute.Media,
            "anime" to ShellRoute.Anime,
            "anime-sources" to ShellRoute.AnimeSources,
            "remote" to ShellRoute.RemoteSettings,
            "settings" to ShellRoute.Settings,
            "management" to ShellRoute.AppManagement,
        )

        assertEquals(expected, defaultShellApps(animeOnly = false).associate { it.id to BuiltInAppRoute.routeFor(it) })
        assertEquals(expected.size, expected.values.toSet().size)
    }

    @Test
    fun backReturnsOneLevelAndHomeAlwaysReturnsToLauncher() {
        var navigation = ShellNavigationState(ShellRoute.RemoteSettings)
        navigation = navigation.reduce(RemoteCommand.Back)
        assertEquals(ShellRoute.Launcher, navigation.route)

        navigation = ShellNavigationState(ShellRoute.Browser("https://duckduckgo.com"))
            .reduce(RemoteCommand.Home)
        assertEquals(ShellRoute.Launcher, navigation.route)
    }

    @Test
    fun statusClockUsesTraditionalChineseWeekday() {
        assertEquals(true, currentTVShellTimeLabel().contains("週"))
    }
}
