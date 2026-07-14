package dev.tvshell.shared

sealed interface ShellRoute {
    data object Launcher : ShellRoute
    data object Anime : ShellRoute
    data object AnimeSources : ShellRoute
    data object YouTube : ShellRoute
    data object Bilibili : ShellRoute
    data object Media : ShellRoute
    data object RemoteSettings : ShellRoute
    data object Settings : ShellRoute
    data object AppManagement : ShellRoute
    data class Browser(val url: String) : ShellRoute
}

object BuiltInAppRoute {
    fun routeFor(app: ShellApp): ShellRoute? = when (app.id) {
        "youtube" -> ShellRoute.YouTube
        "bilibili" -> ShellRoute.Bilibili
        "apple", "browser" -> app.executable?.let(ShellRoute::Browser)
        "video" -> ShellRoute.Media
        "anime" -> ShellRoute.Anime
        "anime-sources" -> ShellRoute.AnimeSources
        "remote" -> ShellRoute.RemoteSettings
        "settings" -> ShellRoute.Settings
        "management" -> ShellRoute.AppManagement
        else -> null
    }
}

data class ShellNavigationState(val route: ShellRoute = ShellRoute.Launcher) {
    fun reduce(command: RemoteCommand): ShellNavigationState = when (command) {
        RemoteCommand.Back, RemoteCommand.Home -> copy(route = ShellRoute.Launcher)
        else -> this
    }
}
