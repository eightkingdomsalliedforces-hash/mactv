package dev.tvshell.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class LauncherStateTest {
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
}
