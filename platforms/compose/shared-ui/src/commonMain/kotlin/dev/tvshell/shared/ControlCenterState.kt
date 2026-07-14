package dev.tvshell.shared

import kotlin.math.round

enum class ControlCenterItem {
    Home,
    FocusMode,
    Audio,
    Display,
    Wallpaper,
    WebZoom,
    Remote,
    Settings,
    DanmakuVisibility,
    DanmakuSize,
    DanmakuSpeed,
    DanmakuOpacity,
    DanmakuDensity;

    val isDanmakuControl: Boolean
        get() = this in DanmakuVisibility..DanmakuDensity

    fun moved(command: RemoteCommand): ControlCenterItem {
        val next = when (command) {
            RemoteCommand.Left -> ordinal - 1
            RemoteCommand.Right -> ordinal + 1
            RemoteCommand.Up -> ordinal - 2
            RemoteCommand.Down -> ordinal + 2
            else -> ordinal
        }.coerceIn(0, entries.lastIndex)
        return entries[next]
    }
}

data class DanmakuSettings(
    val sizeScale: Float = 1f,
    val speedScale: Float = 1f,
    val opacity: Float = .92f,
    val density: Int = 5,
    val isVisible: Boolean = true,
) {
    val sizeLabel: String get() = "${(sizeScale * 100).toInt()}%"
    val speedLabel: String get() = "${(speedScale * 100).toInt()}%"
    val opacityLabel: String get() = "${(opacity * 100).toInt()}%"
    val densityLabel: String get() = "$density 行"

    fun adjusted(item: ControlCenterItem, previous: Boolean): DanmakuSettings {
        val direction = if (previous) -1 else 1
        return when (item) {
            ControlCenterItem.DanmakuVisibility -> copy(isVisible = !isVisible)
            ControlCenterItem.DanmakuSize -> copy(sizeScale = stepped(sizeScale, .1f, direction, .7f, 1.8f))
            ControlCenterItem.DanmakuSpeed -> copy(speedScale = stepped(speedScale, .1f, direction, .6f, 1.8f))
            ControlCenterItem.DanmakuOpacity -> copy(opacity = stepped(opacity, .1f, direction, .35f, 1f))
            ControlCenterItem.DanmakuDensity -> copy(density = (density + direction).coerceIn(1, 10))
            else -> this
        }
    }

    private fun stepped(value: Float, step: Float, direction: Int, minimum: Float, maximum: Float): Float =
        (round((value + step * direction) * 100f) / 100f).coerceIn(minimum, maximum)
}

data class ControlCenterState(
    val focusedItem: ControlCenterItem = ControlCenterItem.Home,
    val isFocusModeEnabled: Boolean = false,
    val volume: Float = .70f,
    val isMuted: Boolean = false,
    val displayScaleIndex: Int = 0,
    val wallpaperIndex: Int = 0,
    val webZoom: Float = 1.25f,
    val isRemoteRunning: Boolean = false,
    val danmaku: DanmakuSettings = DanmakuSettings(),
    val pendingAction: String? = null,
) {
    val displayScaleLabel: String
        get() = listOf("Auto", "100%", "125%", "150%", "200%")[displayScaleIndex]
    val wallpaperLabel: String
        get() = listOf("極光", "暮色", "石墨", "Bing 每日圖片")[wallpaperIndex]

    fun reduce(command: RemoteCommand): ControlCenterState = when (command) {
        RemoteCommand.Left, RemoteCommand.Right -> when {
            focusedItem == ControlCenterItem.Audio -> adjustVolume(if (command == RemoteCommand.Right) .05f else -.05f)
            focusedItem.isDanmakuControl -> copy(danmaku = danmaku.adjusted(focusedItem, command == RemoteCommand.Left))
            else -> copy(focusedItem = focusedItem.moved(command), pendingAction = null)
        }
        RemoteCommand.Up, RemoteCommand.Down -> copy(focusedItem = focusedItem.moved(command), pendingAction = null)
        RemoteCommand.VolumeUp -> adjustVolume(.05f)
        RemoteCommand.VolumeDown -> adjustVolume(-.05f)
        RemoteCommand.Mute -> copy(isMuted = !isMuted, pendingAction = null)
        RemoteCommand.Select -> activateFocusedItem()
        RemoteCommand.Back, RemoteCommand.Menu, RemoteCommand.Home -> copy(pendingAction = "close")
        else -> this
    }

    fun clearAction(): ControlCenterState = copy(pendingAction = null)

    private fun adjustVolume(amount: Float): ControlCenterState {
        val next = (round((volume + amount) * 100f) / 100f).coerceIn(0f, 1f)
        return copy(volume = next, isMuted = if (next > 0f) false else isMuted, pendingAction = null)
    }

    private fun activateFocusedItem(): ControlCenterState = when (focusedItem) {
        ControlCenterItem.Home -> copy(pendingAction = "home")
        ControlCenterItem.FocusMode -> copy(isFocusModeEnabled = !isFocusModeEnabled, pendingAction = null)
        ControlCenterItem.Audio -> copy(isMuted = !isMuted, pendingAction = null)
        ControlCenterItem.Display -> copy(displayScaleIndex = (displayScaleIndex + 1) % 5, pendingAction = null)
        ControlCenterItem.Wallpaper -> copy(wallpaperIndex = (wallpaperIndex + 1) % 4, pendingAction = null)
        ControlCenterItem.WebZoom -> copy(webZoom = if (webZoom >= 2f) 1f else (webZoom + .25f).coerceAtMost(2f), pendingAction = null)
        ControlCenterItem.Remote -> copy(isRemoteRunning = true, pendingAction = "start-remote")
        ControlCenterItem.Settings -> copy(pendingAction = "settings")
        else -> copy(danmaku = danmaku.adjusted(focusedItem, previous = false), pendingAction = null)
    }
}
