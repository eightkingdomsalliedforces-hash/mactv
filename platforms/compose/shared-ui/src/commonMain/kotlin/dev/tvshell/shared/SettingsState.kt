package dev.tvshell.shared

enum class SettingsItem {
    Scale,
    Wallpaper,
    WebZoom,
    VideoSource,
    DanmakuSize,
    DanmakuSpeed,
    DanmakuOpacity,
    DanmakuDensity,
    Credentials;

    val isAdjustable: Boolean get() = this != VideoSource && this != Credentials

    fun moved(command: RemoteCommand): SettingsItem {
        val next = when (command) {
            RemoteCommand.Up -> ordinal - 1
            RemoteCommand.Down -> ordinal + 1
            else -> ordinal
        }.coerceIn(0, entries.lastIndex)
        return entries[next]
    }
}

data class SettingsState(
    val focusedItem: SettingsItem = SettingsItem.Scale,
    val preferences: ControlCenterState = ControlCenterState(),
    val videoSourceLabel: String = "內建示範影片",
    val credentialsSummary: String = "尚未配置",
    val pendingAction: String? = null,
) {
    fun reduce(command: RemoteCommand): SettingsState = when (command) {
        RemoteCommand.Up, RemoteCommand.Down -> copy(focusedItem = focusedItem.moved(command), pendingAction = null)
        RemoteCommand.Left -> if (focusedItem.isAdjustable) adjusted(previous = true) else this
        RemoteCommand.Right -> if (focusedItem.isAdjustable) adjusted(previous = false) else this
        RemoteCommand.Select -> if (focusedItem.isAdjustable) adjusted(previous = false) else when (focusedItem) {
            SettingsItem.VideoSource -> copy(pendingAction = "video-source")
            SettingsItem.Credentials -> copy(pendingAction = "credentials")
            else -> this
        }
        RemoteCommand.Back, RemoteCommand.Home -> copy(pendingAction = "exit")
        else -> this
    }

    fun clearAction(): SettingsState = copy(pendingAction = null)

    private fun adjusted(previous: Boolean): SettingsState {
        val nextPreferences = when (focusedItem) {
            SettingsItem.Scale -> preferences.copy(displayScaleIndex = cycle(preferences.displayScaleIndex, 5, previous))
            SettingsItem.Wallpaper -> preferences.copy(wallpaperIndex = cycle(preferences.wallpaperIndex, 4, previous))
            SettingsItem.WebZoom -> preferences.copy(
                webZoom = if (previous) (preferences.webZoom - .1f).coerceAtLeast(.8f)
                else (preferences.webZoom + .1f).coerceAtMost(2.4f),
            )
            SettingsItem.DanmakuSize -> preferences.copy(
                danmaku = preferences.danmaku.adjusted(ControlCenterItem.DanmakuSize, previous),
            )
            SettingsItem.DanmakuSpeed -> preferences.copy(
                danmaku = preferences.danmaku.adjusted(ControlCenterItem.DanmakuSpeed, previous),
            )
            SettingsItem.DanmakuOpacity -> preferences.copy(
                danmaku = preferences.danmaku.adjusted(ControlCenterItem.DanmakuOpacity, previous),
            )
            SettingsItem.DanmakuDensity -> preferences.copy(
                danmaku = preferences.danmaku.adjusted(ControlCenterItem.DanmakuDensity, previous),
            )
            else -> preferences
        }
        return copy(preferences = nextPreferences, pendingAction = null)
    }

    private fun cycle(current: Int, count: Int, previous: Boolean): Int =
        if (previous) (current - 1 + count) % count else (current + 1) % count
}
