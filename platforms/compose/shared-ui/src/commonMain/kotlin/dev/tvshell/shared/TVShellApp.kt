package dev.tvshell.shared

import androidx.compose.animation.core.tween
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.itemsIndexed as gridItemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import dev.tvshell.shared.anime.AnimeEpisode
import dev.tvshell.shared.anime.AnimeStreamCandidate
import dev.tvshell.shared.anime.DanmakuComment
import dev.tvshell.shared.anime.DanmakuMotion
import dev.tvshell.shared.anime.DanmakuTimeline
import dev.tvshell.shared.anime.TorrentStartRequest
import dev.tvshell.shared.anime.TorrentTransferPhase
import dev.tvshell.shared.anime.TorrentTransferSnapshot
import dev.tvshell.shared.anime.MagnetLink
import dev.tvshell.shared.anime.TorrentIdentity

internal fun torrentGenerationToBackground(
    previousGeneration: Long?,
    nextGeneration: Long?,
    action: String?,
): Long? = previousGeneration?.takeIf {
    it != nextGeneration &&
        (action?.startsWith("load:") == true || action?.startsWith("torrent:start:") == true)
}

@Composable
fun TVShellApp(
    adapter: PlatformAdapter,
    animeOnly: Boolean = false,
    appsRevision: Int = 0,
    dispatcher: RemoteCommandDispatcher? = null,
    externalMagnetRequest: ExternalMagnetRequest? = null,
) {
    val initialMagnet = remember {
        externalMagnetRequest?.let { request ->
            runCatching { externalMagnetPlayback(request.magnet) }.getOrNull()
        }
    }
    val discovered = remember(appsRevision) { adapter.installedApps() }
    val builtIns = remember(animeOnly) { defaultShellApps(animeOnly) }
    val restoredPreferences = remember(adapter) { adapter.loadPreferences().getOrDefault(ShellPreferences()) }
    var state by remember(discovered) {
        mutableStateOf(
            LauncherState(
                (builtIns + discovered).distinctBy { it.id },
                historyCount = restoredPreferences.history.entries.size,
            ),
        )
    }
    var screen by remember { mutableStateOf<ShellRoute>(if (animeOnly || initialMagnet != null) ShellRoute.Anime else ShellRoute.Launcher) }
    var animeState by remember {
        mutableStateOf(
            initialMagnet?.let { CrossPlatformAnimeBrowserState().openingMagnet(it.candidate) }
                ?: CrossPlatformAnimeBrowserState().loadingFirstSource(),
        )
    }
    var animeCards by remember { mutableStateOf(initialMagnet?.let { listOf(it.card) }.orEmpty()) }
    var animeEpisodes by remember { mutableStateOf(initialMagnet?.let { listOf(it.episode) }.orEmpty()) }
    var animeStatus by remember {
        mutableStateOf(initialMagnet?.let { "Magnet：正在啟動 ${it.card.title}…" } ?: "正在載入推薦動畫…")
    }
    var animeDanmaku by remember { mutableStateOf(emptyList<DanmakuComment>()) }
    var animeDanmakuStatus by remember { mutableStateOf("彈幕尚未載入") }
    var animePlaybackSeconds by remember { mutableStateOf(0.0) }
    var animePlaybackDurationSeconds by remember { mutableStateOf(0.0) }
    var animeTorrentSnapshot by remember { mutableStateOf(TorrentTransferSnapshot()) }
    var animeWebState by remember { mutableStateOf(WebRuntimeState("about:blank")) }
    var mediaState by remember { mutableStateOf(NativeMediaState(0)) }
    var mediaCards by remember { mutableStateOf(emptyList<NativeMediaCard>()) }
    var mediaStatus by remember { mutableStateOf("正在載入…") }
    var browserState by remember { mutableStateOf(WebRuntimeState("https://duckduckgo.com")) }
    var mediaWebState by remember { mutableStateOf(WebRuntimeState("about:blank")) }
    var watchHistory by remember { mutableStateOf(restoredPreferences.history) }
    var controlCenterVisible by remember { mutableStateOf(false) }
    var controlCenterState by remember { mutableStateOf(restoredPreferences.controlCenter) }
    var animeSourceSettings by remember { mutableStateOf(restoredPreferences.animeSources) }
    var animeSourceManagementState by remember { mutableStateOf(AnimeSourceManagementState()) }
    var remoteSettingsState by remember { mutableStateOf(NavigationListState(rowCount = 8)) }
    var appManagementState by remember(state.apps.size) { mutableStateOf(NavigationListState(rowCount = state.apps.size)) }
    var settingsState by remember {
        mutableStateOf(
            SettingsState(
                preferences = restoredPreferences.controlCenter,
                credentialsLocation = adapter.credentialsLocation(),
            ),
        )
    }
    var wallpaperURL by remember { mutableStateOf<String?>(null) }
    var clockLabel by remember { mutableStateOf(currentTVShellTimeLabel()) }
    var handledMagnetSequence by remember { mutableStateOf(initialMagnet?.let { externalMagnetRequest?.sequence }) }
    val activeDispatcher = remember(dispatcher) { dispatcher ?: RemoteCommandDispatcher() }
    val handleRootKeyEvents = shouldHandleRootKeyEvent(dispatcher != null)
    val focusRequester = remember { FocusRequester() }
    val rootFocusBootstrap = remember { RootFocusBootstrap() }

    fun recordWatch(card: NativeMediaCard) {
        watchHistory = watchHistory.record(card)
        state = state.copy(historyCount = watchHistory.entries.size)
        adapter.savePreferences(ShellPreferences(animeSourceSettings, watchHistory, controlCenterState))
    }

    fun openExternalMagnet(rawMagnet: String): Result<Unit> = runCatching {
        val playback = externalMagnetPlayback(rawMagnet)
        animeState.activeTorrentGeneration?.let(adapter::cancelAnimeTorrentAutoplay)
        adapter.stopAnime()
        screen = ShellRoute.Anime
        animeCards = listOf(playback.card)
        animeEpisodes = listOf(playback.episode)
        animeDanmaku = emptyList()
        animePlaybackSeconds = 0.0
        animePlaybackDurationSeconds = 0.0
        animeTorrentSnapshot = TorrentTransferSnapshot()
        animeState = animeState.openingMagnet(playback.candidate)
        animeStatus = "Magnet：正在啟動 ${playback.card.title}…"
    }

    fun handle(command: RemoteCommand) {
        if (controlCenterVisible) {
            val next = controlCenterState.reduce(command)
            when (next.pendingAction) {
                "close" -> controlCenterVisible = false
                "home" -> {
                    controlCenterVisible = false
                    screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
                }
                "settings" -> {
                    controlCenterVisible = false
                    settingsState = SettingsState(
                        preferences = controlCenterState,
                        credentialsLocation = adapter.credentialsLocation(),
                    )
                    screen = ShellRoute.Settings
                }
            }
            controlCenterState = next.clearAction()
            adapter.savePreferences(ShellPreferences(animeSourceSettings, watchHistory, controlCenterState))
            return
        }
        if (command == RemoteCommand.Menu && !(screen == ShellRoute.Launcher && state.focus == LauncherFocus.History) && !(
                screen == ShellRoute.Anime &&
                    (animeState.phase == CrossPlatformAnimePhase.Playing ||
                        animeState.phase == CrossPlatformAnimePhase.Buffering ||
                        animeState.phase == CrossPlatformAnimePhase.Episodes ||
                        animeState.isStreamPickerVisible ||
                        animeState.downloadManager.isVisible)
                )) {
            controlCenterVisible = true
            return
        }
        if (screen == ShellRoute.Settings) {
            val next = settingsState.reduce(command)
            when (next.pendingAction) {
                "exit" -> screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
                "video-source" -> {
                    mediaWebState = WebRuntimeState("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
                    screen = ShellRoute.Media
                }
                "credentials" -> adapter.openCredentialsImporter()
            }
            controlCenterState = next.preferences
            settingsState = next.clearAction()
            adapter.savePreferences(ShellPreferences(animeSourceSettings, watchHistory, controlCenterState))
            return
        }
        if (screen is ShellRoute.Browser) {
            val next = browserState.reduce(command)
            if (next.pendingAction == "exit") screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
            browserState = next.clearAction()
            return
        }
        if (screen == ShellRoute.Media) {
            val next = mediaWebState.reduce(playerWebCommand(command))
            if (command == RemoteCommand.Back || next.pendingAction == "exit") {
                adapter.stopAnime()
                screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
            }
            mediaWebState = next.clearAction()
            return
        }
        if (screen == ShellRoute.AnimeSources) {
            val next = animeSourceManagementState.reduce(command)
            when (next.pendingAction) {
                "toggle-css1" -> animeSourceSettings = animeSourceSettings.copy(css1Enabled = !animeSourceSettings.css1Enabled)
                "reset-css1" -> animeSourceSettings = animeSourceSettings.resetCSS1()
                "exit" -> screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
            }
            animeSourceManagementState = next.clearAction()
            adapter.savePreferences(ShellPreferences(animeSourceSettings, watchHistory, controlCenterState))
            return
        }
        if (screen == ShellRoute.RemoteSettings) {
            val next = remoteSettingsState.reduce(command)
            if (next.pendingAction == "exit") screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
            remoteSettingsState = next.clearAction()
            return
        }
        if (screen == ShellRoute.AppManagement) {
            val next = appManagementState.reduce(command)
            when {
                next.pendingAction == "exit" -> screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
                next.pendingAction?.startsWith("select:") == true -> {
                    val index = next.pendingAction.substringAfter(':').toIntOrNull() ?: 0
                    state.apps.getOrNull(index)?.let { app ->
                        val route = BuiltInAppRoute.routeFor(app)
                        if (route != null) {
                            screen = route
                            if (route is ShellRoute.Browser) browserState = WebRuntimeState(route.url)
                            if (route == ShellRoute.Media) mediaWebState = WebRuntimeState("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
                        } else {
                            state = state.copy(status = adapter.launch(app).fold(
                                { "正在開啟 ${app.name}" },
                                { "無法開啟 ${app.name}：${it.message}" },
                            ))
                        }
                    }
                }
            }
            appManagementState = next.clearAction()
            return
        }
        if (screen == ShellRoute.YouTube || screen == ShellRoute.Bilibili) {
            if ((command == RemoteCommand.Back || command == RemoteCommand.Home) && mediaState.phase == NativeMediaPhase.Browser) {
                screen = ShellRoute.Launcher
            } else {
                val wasPlaying = mediaState.phase == NativeMediaPhase.Player
                val next = mediaState.reduce(command)
                if (wasPlaying && next.phase == NativeMediaPhase.Browser) adapter.stopAnime()
                val action = next.pendingAction
                if (action?.startsWith("open-internal:") == true) {
                    val index = action.substringAfter(':').toIntOrNull() ?: 0
                    mediaCards.getOrNull(index)?.let { card ->
                        mediaWebState = WebRuntimeState(card.playbackURL)
                        recordWatch(card)
                        mediaStatus = "正在 TVShell 內建播放器播放 ${card.title}"
                    }
                    mediaState = next.clearAction()
                } else {
                    mediaState = next
                    if (mediaState.phase == NativeMediaPhase.Player) {
                        mediaWebState = mediaWebState.reduce(playerWebCommand(command)).clearAction()
                    }
                }
            }
            return
        }
        if (screen == ShellRoute.Anime) {
            val previousTorrentGeneration = animeState.activeTorrentGeneration
            var next = animeState.reduce(command)
            val tabChanged = next.focusedTopTab != animeState.focusedTopTab
            if (tabChanged) {
                next = when (next.focusedTopTab) {
                    AnimeTopTab.Recommended -> next.loadingFirstSource()
                    AnimeTopTab.History -> next.copy(
                        phase = CrossPlatformAnimePhase.Titles,
                        cardCount = watchHistory.entries.size,
                        isTopNavigationFocused = true,
                    )
                    else -> next
                }
            }
            val action = next.pendingAction
            torrentGenerationToBackground(
                previousGeneration = previousTorrentGeneration,
                nextGeneration = next.activeTorrentGeneration,
                action = action,
            )?.let(adapter::cancelAnimeTorrentAutoplay)
            when {
                action == "exit" -> {
                    animeState = next.clearAction()
                    if (animeOnly) adapter.exitApp() else screen = ShellRoute.Launcher
                }
                action == "play" -> {
                    animeWebState = animeWebState.reduce(RemoteCommand.PlayPause).clearAction()
                    animeStatus = "繼續播放"
                    animeState = next.clearAction()
                }
                action == "pause" -> {
                    animeWebState = animeWebState.reduce(RemoteCommand.PlayPause).clearAction()
                    animeStatus = "已暫停"
                    animeState = next.clearAction()
                }
                action?.startsWith("seek:") == true -> {
                    val seconds = action.substringAfter(':').toIntOrNull() ?: 0
                    animePlaybackSeconds = (animePlaybackSeconds + seconds).coerceAtLeast(0.0)
                    animeWebState = animeWebState.reduce(if (seconds >= 0) RemoteCommand.FastForward else RemoteCommand.Rewind).clearAction()
                    animeStatus = if (seconds >= 0) "快轉 ${seconds} 秒" else "倒轉 ${-seconds} 秒"
                    animeState = next.clearAction()
                }
                action == "volume:up" || action == "volume:down" -> {
                    val direction = if (action.endsWith("up")) 1 else -1
                    animeWebState = animeWebState.reduce(if (direction > 0) RemoteCommand.VolumeUp else RemoteCommand.VolumeDown).clearAction()
                    animeStatus = if (direction > 0) "音量提高" else "音量降低"
                    animeState = next.clearAction()
                }
                action == "volume:mute" -> {
                    animeWebState = animeWebState.reduce(RemoteCommand.Mute).clearAction()
                    animeStatus = "已切換靜音"
                    animeState = next.clearAction()
                }
                action == "stop" -> {
                    next.activeTorrentGeneration?.let(adapter::cancelAnimeTorrentAutoplay)
                    adapter.stopAnime()
                    animeDanmaku = emptyList()
                    animePlaybackSeconds = 0.0
                    animePlaybackDurationSeconds = 0.0
                    animeStatus = "已回到選集。"
                    animeState = next.clearAction()
                }
                action == "home" -> {
                    next.activeTorrentGeneration?.let(adapter::cancelAnimeTorrentAutoplay)
                    adapter.stopAnime()
                    animeDanmaku = emptyList()
                    animePlaybackSeconds = 0.0
                    animePlaybackDurationSeconds = 0.0
                    animeState = next.copy(phase = CrossPlatformAnimePhase.Episodes).clearAction()
                    if (animeOnly) adapter.exitApp() else screen = ShellRoute.Launcher
                }
                action?.startsWith("torrent:background:") == true -> {
                    val generation = action.substringAfterLast(':').toLongOrNull()
                    if (generation != null) adapter.cancelAnimeTorrentAutoplay(generation)
                    animeStatus = "BT 已留在背景下載，可從 Menu 的下載管理查看。"
                    animeTorrentSnapshot = adapter.animeTorrentSnapshot()
                    animeState = next.clearAction()
                }
                action == "torrent:cancel" -> {
                    animeState = next.clearAction()
                }
                else -> {
                    animeState = next
                }
            }
            return
        }
        when (command) {
            RemoteCommand.Select -> when (state.focus) {
                LauncherFocus.History -> watchHistory.entries.getOrNull(state.focusedHistoryIndex)?.let { card ->
                    if (card.playbackURL.trim().startsWith("magnet:?", ignoreCase = true)) {
                        openExternalMagnet(card.playbackURL).onFailure {
                            state = state.copy(status = "Magnet 無法開啟：${it.message ?: "格式錯誤"}")
                        }
                        return@let
                    }
                    mediaWebState = WebRuntimeState(card.playbackURL)
                    state = state.copy(status = "正在 TVShell 內建播放器續播 ${card.title}")
                    screen = ShellRoute.Media
                }
                LauncherFocus.Apps -> state.focusedApp?.let { app ->
                    BuiltInAppRoute.routeFor(app)?.let { route ->
                        screen = route
                        if (route is ShellRoute.Browser) browserState = WebRuntimeState(route.url)
                        if (route == ShellRoute.Media) {
                            mediaWebState = WebRuntimeState("https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
                        }
                        return@let
                    }
                    val result = if (app.isSystemSettings) adapter.openSystemSettings() else adapter.launch(app)
                    state = state.copy(status = result.fold({ "正在開啟 ${app.name}" }, { "無法開啟 ${app.name}：${it.message}" }))
                }
            }
            RemoteCommand.Home, RemoteCommand.Back -> {
                controlCenterVisible = false
                screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
            }
            else -> {
                val next = state.reduce(command)
                if (next.pendingAction?.startsWith("delete-history:") == true) {
                    val index = next.pendingAction.substringAfter(':').toIntOrNull() ?: -1
                    watchHistory.entries.getOrNull(index)?.let { entry ->
                        watchHistory = watchHistory.delete(entry.id)
                        adapter.savePreferences(ShellPreferences(animeSourceSettings, watchHistory, controlCenterState))
                    }
                    state = next.historyDeleted(watchHistory.entries.size)
                } else {
                    state = next
                }
            }
        }
    }

    DisposableEffect(activeDispatcher) {
        val unsubscribe = activeDispatcher.subscribe(::handle)
        onDispose(unsubscribe)
    }
    DisposableEffect(adapter) {
        onDispose(adapter::close)
    }
    LaunchedEffect(externalMagnetRequest?.sequence, externalMagnetRequest?.magnet) {
        val request = externalMagnetRequest ?: return@LaunchedEffect
        if (handledMagnetSequence == request.sequence) return@LaunchedEffect
        handledMagnetSequence = request.sequence
        openExternalMagnet(request.magnet).fold(
            onSuccess = {},
            onFailure = { error ->
                screen = ShellRoute.Anime
                animeStatus = "Magnet 無法開啟：${error.message ?: "格式錯誤"}"
            },
        )
    }
    LaunchedEffect(Unit) {
        wallpaperURL = withContext(Dispatchers.Default) { adapter.fetchWallpaperURL().getOrNull() }
    }
    LaunchedEffect(Unit) {
        while (true) {
            clockLabel = currentTVShellTimeLabel()
            delay(30_000)
        }
    }
    LaunchedEffect(screen, mediaState.focusedTab) {
        val service = when (screen) {
            ShellRoute.YouTube -> NativeMediaService.YouTube
            ShellRoute.Bilibili -> NativeMediaService.Bilibili
            else -> null
        } ?: return@LaunchedEffect
        val bilibiliSection = if (service == NativeMediaService.Bilibili) {
            BilibiliSection.entries.getOrElse(mediaState.focusedTab) { BilibiliSection.Recommended }
        } else null
        val label = bilibiliSection?.title ?: "YouTube"
        mediaStatus = "正在載入 $label…"
        val result = withContext(Dispatchers.Default) {
            if (bilibiliSection != null) adapter.fetchBilibiliSection(bilibiliSection) else adapter.fetchMediaFeed(service)
        }
        result.fold(
            onSuccess = { cards ->
                mediaCards = cards
                mediaState = NativeMediaState(
                    cardCount = cards.size,
                    tabCount = if (service == NativeMediaService.Bilibili) BilibiliSection.entries.size else 4,
                    focusedTab = mediaState.focusedTab,
                )
                mediaStatus = "$label · 已載入 ${cards.size} 筆內容"
            },
            onFailure = {
                mediaCards = emptyList()
                mediaState = NativeMediaState(
                    cardCount = 0,
                    tabCount = if (service == NativeMediaService.Bilibili) BilibiliSection.entries.size else 4,
                    focusedTab = mediaState.focusedTab,
                )
                mediaStatus = "$label 載入失敗：${it.message}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.focusedTopTab, animeState.focusedSource) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.Loading) return@LaunchedEffect
        val source = animeSourcesFor(animeState.focusedTopTab).getOrNull(animeState.focusedSource)
        if (source == null) {
            animeCards = emptyList()
            animeState = animeState.failed()
            animeStatus = when (animeState.focusedTopTab) {
                AnimeTopTab.History -> "目前沒有動畫觀看記錄。"
                AnimeTopTab.Search -> "按 Menu 開啟搜尋。"
                else -> "這個分頁目前沒有來源。"
            }
            return@LaunchedEffect
        }
        animeStatus = "正在載入${source.title}…"
        withContext(Dispatchers.Default) { adapter.fetchAnimeFeed(source.kind) }.fold(
            onSuccess = { cards ->
                animeCards = cards
                animeState = animeState.loaded(cards.size)
                animeStatus = "${source.title} · 已載入 ${cards.size} 部內容"
            },
            onFailure = {
                animeCards = emptyList()
                animeState = animeState.failed()
                animeStatus = "${source.title} 載入失敗：${it.message ?: "未知原因"}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.selectedCardIndex) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.EpisodeLoading) return@LaunchedEffect
        val cards = if (animeState.focusedTopTab == AnimeTopTab.History) watchHistory.entries else animeCards
        val card = cards.getOrNull(animeState.selectedCardIndex)
        if (card == null) {
            animeStatus = "找不到選取的作品。"
            animeState = animeState.copy(phase = CrossPlatformAnimePhase.Titles, pendingAction = null)
            return@LaunchedEffect
        }
        val source = card.animeSource ?: animeSourcesFor(animeState.focusedTopTab).getOrNull(animeState.focusedSource)?.kind
        if (source == null) {
            animeStatus = "無法判斷這筆觀看記錄的動畫來源。"
            animeState = animeState.copy(phase = CrossPlatformAnimePhase.Details, pendingAction = null)
            return@LaunchedEffect
        }
        animeStatus = "正在載入 ${card.title} 選集…"
        withContext(Dispatchers.Default) { adapter.fetchAnimeEpisodes(source, card) }.fold(
            onSuccess = { episodes ->
                animeEpisodes = episodes
                animeState = animeState.episodesLoaded(episodes.size)
                animeStatus = "${card.title} · 已載入 ${episodes.size} 集"
            },
            onFailure = {
                animeEpisodes = emptyList()
                animeState = animeState.copy(phase = CrossPlatformAnimePhase.Details, pendingAction = null)
                animeStatus = "選集載入失敗：${it.message ?: "未知原因"}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.pendingAction) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.Resolving) return@LaunchedEffect
        val action = animeState.pendingAction ?: return@LaunchedEffect
        if (!action.startsWith("streams:")) return@LaunchedEffect
        val index = action.substringAfter(':').toIntOrNull() ?: animeState.focusedEpisode
        val episode = animeEpisodes.getOrNull(index)
        if (episode == null) {
            animeStatus = "找不到選取的集數。"
            animeState = animeState.copy(phase = CrossPlatformAnimePhase.Episodes, pendingAction = null)
            return@LaunchedEffect
        }
        val cards = if (animeState.focusedTopTab == AnimeTopTab.History) watchHistory.entries else animeCards
        val card = cards.getOrNull(animeState.selectedCardIndex)
        val source = card?.animeSource ?: animeSourcesFor(animeState.focusedTopTab).getOrNull(animeState.focusedSource)?.kind
        if (source == null) {
            animeStatus = "無法判斷播放來源。"
            animeState = animeState.copy(phase = CrossPlatformAnimePhase.Episodes, pendingAction = null)
            return@LaunchedEffect
        }
        animeStatus = "正在解析 ${episode.title}…"
        withContext(Dispatchers.Default) { adapter.resolveAnimeStreams(source, episode) }.fold(
            onSuccess = { candidates ->
                animeState = animeState.streamsLoaded(candidates)
                animeStatus = if (candidates.size > 1) {
                    "找到 ${candidates.size} 個播放結果，請選擇播放線。"
                } else {
                    "播放源：${candidates.firstOrNull()?.quality ?: "沒有可用播放源"}"
                }
            },
            onFailure = {
                animeState = animeState.copy(phase = CrossPlatformAnimePhase.Episodes, pendingAction = null)
                animeStatus = "解析失敗：${it.message ?: "未知原因"}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.pendingAction, animeState.selectedStreamIndex) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.Buffering) return@LaunchedEffect
        val action = animeState.pendingAction ?: return@LaunchedEffect
        if (!action.startsWith("torrent:start:")) return@LaunchedEffect
        val index = action.substringAfterLast(':').toIntOrNull() ?: animeState.selectedStreamIndex
        val candidate = animeState.streamCandidates.getOrNull(index) ?: return@LaunchedEffect
        val cards = if (animeState.focusedTopTab == AnimeTopTab.History) watchHistory.entries else animeCards
        val card = cards.getOrNull(animeState.selectedCardIndex)
        val episode = animeEpisodes.getOrNull(animeState.focusedEpisode)
        animeWebState = WebRuntimeState("about:blank")
        animeTorrentSnapshot = TorrentTransferSnapshot()
        animeStatus = "BT：正在啟動內建磁力引擎…"
        val request = TorrentStartRequest(
            magnet = candidate.url,
            episodeNumber = episode?.number,
            title = card?.title ?: "動畫",
            subtitle = episode?.title ?: candidate.quality,
            quality = candidate.quality,
        )
        // startAnimeTorrent only schedules native work and returns its generation.
        // Keep this ownership hand-off on the UI dispatcher so Back/Home cannot
        // race between starting a task and recording the generation that owns it.
        adapter.startAnimeTorrent(request).fold(
            onSuccess = { generation ->
                animeState = animeState.torrentStarted(generation)
                animeTorrentSnapshot = adapter.animeTorrentSnapshot()
                animeStatus = animeTorrentSnapshot.statusText
            },
            onFailure = {
                animeStatus = "BT 啟動失敗：${it.message ?: "未知原因"}"
                animeState = animeState.copy(
                    phase = CrossPlatformAnimePhase.Episodes,
                    isPlaying = false,
                    pendingAction = null,
                )
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.activeTorrentGeneration) {
        val generation = animeState.activeTorrentGeneration ?: return@LaunchedEffect
        if (screen != ShellRoute.Anime || animeState.phase !in setOf(CrossPlatformAnimePhase.Buffering, CrossPlatformAnimePhase.Playing)) {
            return@LaunchedEffect
        }
        while (animeState.activeTorrentGeneration == generation &&
            animeState.phase in setOf(CrossPlatformAnimePhase.Buffering, CrossPlatformAnimePhase.Playing)) {
            val snapshot = withContext(Dispatchers.Default) { adapter.animeTorrentSnapshot() }
            if (snapshot.generation == generation) {
                animeTorrentSnapshot = snapshot
                if (animeState.phase == CrossPlatformAnimePhase.Buffering) animeStatus = snapshot.statusText
                if (snapshot.phase == TorrentTransferPhase.Failed) {
                    animeStatus = snapshot.statusText
                    animeState = animeState.torrentFailed(generation)
                    break
                }
                val playable = adapter.consumeAnimeTorrentPlayableStream(generation)
                if (playable != null && animeState.phase == CrossPlatformAnimePhase.Buffering) {
                    val resolved = AnimeStreamCandidate(
                        url = playable.url,
                        quality = "${playable.quality} · BT 邊下邊播",
                        headers = mapOf("resolver" to "torrent-stream", "X-TVShell-Torrent-ID" to playable.taskID),
                    )
                    animeState = animeState.torrentReady(generation, resolved)
                    animeStatus = "BT 已緩衝完成：${playable.selectedPath}"
                }
            }
            delay(250)
        }
    }
    LaunchedEffect(screen, animeState.downloadManager.isVisible, animeState.pendingAction) {
        if (screen != ShellRoute.Anime || !animeState.downloadManager.isVisible) return@LaunchedEffect
        val action = animeState.pendingAction ?: return@LaunchedEffect
        when {
            action == "downloads:refresh" -> withContext(Dispatchers.Default) { adapter.animeTorrentDownloads() }.fold(
                onSuccess = { animeState = animeState.downloadsLoaded(it) },
                onFailure = {
                    animeStatus = "下載管理載入失敗：${it.message ?: "未知原因"}"
                    animeState = animeState.clearAction()
                },
            )
            action.startsWith("delete:") -> {
                val id = action.substringAfter(':')
                withContext(Dispatchers.Default) { adapter.deleteAnimeTorrentDownload(id) }.fold(
                    onSuccess = {
                        animeStatus = "已刪除 BT 快取。"
                        animeState = animeState.torrentDownloadDeleted(id)
                    },
                    onFailure = {
                        animeStatus = "刪除失敗：${it.message ?: "未知原因"}"
                        animeState = animeState.clearAction()
                    },
                )
            }
        }
    }
    LaunchedEffect(screen, animeState.phase, animeState.pendingAction, animeState.selectedStreamIndex) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.Playing) return@LaunchedEffect
        val action = animeState.pendingAction ?: return@LaunchedEffect
        if (!action.startsWith("load:")) return@LaunchedEffect
        val candidate = animeState.activePlayerCandidate ?: return@LaunchedEffect
        animeWebState = WebRuntimeState(candidate.url)
        withContext(Dispatchers.Default) { adapter.loadAnimeStream(candidate) }.fold(
            onSuccess = {
                val cards = if (animeState.focusedTopTab == AnimeTopTab.History) watchHistory.entries else animeCards
                cards.getOrNull(animeState.selectedCardIndex)?.let { card ->
                    val episode = animeEpisodes.getOrNull(animeState.focusedEpisode)
                    val torrentCandidate = animeState.streamCandidates.getOrNull(animeState.selectedStreamIndex)
                        ?.takeIf { it.url.startsWith("magnet:?", ignoreCase = true) || it.headers["resolver"] == "torrent" }
                    val historyCard = if (episode != null && torrentCandidate != null) {
                        runCatching { dev.tvshell.shared.anime.MagnetHistoryReplay.card(card, episode, torrentCandidate) }
                            .getOrDefault(card)
                    } else {
                        card
                    }
                    recordWatch(historyCard)
                }
                animeStatus = "播放源：${candidate.quality}"
                animePlaybackSeconds = 0.0
                animePlaybackDurationSeconds = 0.0
                animeState = animeState.clearAction()
            },
            onFailure = {
                val failedTorrentGeneration = animeState.activeTorrentGeneration
                adapter.stopAnime()
                failedTorrentGeneration?.let(adapter::cancelAnimeTorrentAutoplay)
                animeStatus = "播放失敗：${it.message ?: "未知原因"}"
                animeState = animeState.copy(
                    phase = CrossPlatformAnimePhase.Episodes,
                    resolvedPlaybackCandidate = null,
                    activeTorrentGeneration = null,
                    isPlaying = false,
                    pendingAction = null,
                )
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.selectedCardIndex, animeState.focusedEpisode) {
        if (screen != ShellRoute.Anime || animeState.phase != CrossPlatformAnimePhase.Playing) return@LaunchedEffect
        val cards = if (animeState.focusedTopTab == AnimeTopTab.History) watchHistory.entries else animeCards
        val card = cards.getOrNull(animeState.selectedCardIndex) ?: return@LaunchedEffect
        val episode = animeEpisodes.getOrNull(animeState.focusedEpisode) ?: return@LaunchedEffect
        val source = card.animeSource
            ?: animeSourcesFor(animeState.focusedTopTab).getOrNull(animeState.focusedSource)?.kind
            ?: return@LaunchedEffect
        animeDanmaku = emptyList()
        animeDanmakuStatus = "正在載入彈幕…"
        withContext(Dispatchers.Default) { adapter.fetchAnimeDanmaku(source, card, episode) }.fold(
            onSuccess = { comments ->
                animeDanmaku = comments
                animeDanmakuStatus = if (comments.isEmpty()) "搜不到彈幕" else "彈幕 ${comments.size} 條"
            },
            onFailure = {
                animeDanmaku = emptyList()
                animeDanmakuStatus = "彈幕未載入：${it.message ?: "未知原因"}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.activePlayerCandidate?.url) {
        while (screen == ShellRoute.Anime && animeState.phase == CrossPlatformAnimePhase.Playing) {
            val playback = withContext(Dispatchers.Default) { adapter.animePlaybackSnapshot() }
            if (!playback.error.isNullOrBlank()) {
                val failedGeneration = animeState.activeTorrentGeneration
                adapter.stopAnime()
                failedGeneration?.let(adapter::cancelAnimeTorrentAutoplay)
                animeStatus = "播放失敗：${playback.error}"
                animeState = animeState.copy(
                    phase = CrossPlatformAnimePhase.Episodes,
                    resolvedPlaybackCandidate = null,
                    activeTorrentGeneration = null,
                    isPlaying = false,
                    pendingAction = null,
                )
                break
            }
            if (playback.positionSeconds > 0.0 || playback.durationSeconds > 0.0 || playback.isPlaying) {
                animePlaybackSeconds = playback.positionSeconds.coerceAtLeast(0.0)
                animePlaybackDurationSeconds = playback.durationSeconds.coerceAtLeast(0.0)
            } else if (animeState.activePlayerCandidate?.headers?.get("resolver") == "official" && animeState.isPlaying) {
                animePlaybackSeconds += .25
            }
            delay(250)
        }
    }
    LaunchedEffect(animeState.phase, animeState.isPlayerHUDVisible, animeState.pendingAction) {
        if (animeState.phase == CrossPlatformAnimePhase.Playing && animeState.isPlayerHUDVisible) {
            delay(3_000)
            animeState = animeState.hidePlayerHUD()
        }
    }

    TVShellBackdrop(if (animeOnly) null else wallpaperURL) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val canvasScale = referenceCanvasScale(maxWidth.value, maxHeight.value)
            Box(
                Modifier.width(1920.dp).height(1080.dp)
                    .align(Alignment.Center)
                    .graphicsLayer(scaleX = canvasScale, scaleY = canvasScale)
            .onPreviewKeyEvent { event ->
                if (!handleRootKeyEvents) return@onPreviewKeyEvent false
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                desktopKeyToRemoteCommand(event.key, event.isShiftPressed)?.let { handle(it); true } ?: false
            }
            .focusRequester(focusRequester)
            .focusable()
            .onGloballyPositioned {
                rootFocusBootstrap.requestOnce(focusRequester::requestFocus)
            }
        ) {
        AnimatedContent(
            targetState = screen,
            transitionSpec = {
                (fadeIn(tween(TVShellVisual.RuntimeAnimationMilliseconds)) + slideInVertically(
                    animationSpec = tween(TVShellVisual.RuntimeAnimationMilliseconds),
                    initialOffsetY = { it / 18 },
                )).togetherWith(
                    fadeOut(tween(TVShellVisual.RuntimeAnimationMilliseconds / 2)) + slideOutVertically(
                        animationSpec = tween(TVShellVisual.RuntimeAnimationMilliseconds / 2),
                        targetOffsetY = { -it / 28 },
                    ),
                )
            },
            label = "TVShell screen transition",
        ) { visibleScreen ->
            when (visibleScreen) {
                ShellRoute.Launcher -> Launcher(state, watchHistory.entries)
                ShellRoute.Anime -> AnimatedContent(
                    targetState = animeState.phase,
                    transitionSpec = {
                        fadeIn(tween(TVShellVisual.RuntimeAnimationMilliseconds))
                            .togetherWith(fadeOut(tween(TVShellVisual.RuntimeAnimationMilliseconds / 2)))
                    },
                    label = "Anime phase transition",
                ) { visiblePhase ->
                    AnimeBrowser(
                        animeState.copy(phase = visiblePhase),
                        animeCards,
                        watchHistory.entries,
                        animeEpisodes,
                        animeStatus,
                        animeDanmaku,
                        animeDanmakuStatus,
                        animePlaybackSeconds,
                        animePlaybackDurationSeconds,
                        controlCenterState.danmaku,
                        animeWebState,
                        animeTorrentSnapshot,
                    )
                }
                ShellRoute.YouTube -> NativeMediaRoute("YouTube", listOf("推薦", "熱門", "訂閱", "搜尋"), mediaState, mediaCards, mediaStatus, mediaWebState) {
                    mediaState = mediaState.copy(phase = NativeMediaPhase.Browser)
                }
                ShellRoute.Bilibili -> NativeMediaRoute("Bilibili", BilibiliSection.entries.map(BilibiliSection::title), mediaState, mediaCards, mediaStatus, mediaWebState) {
                    mediaState = mediaState.copy(phase = NativeMediaPhase.Browser)
                }
                ShellRoute.Settings -> SettingsScreen(settingsState)
                ShellRoute.RemoteSettings -> RemoteSettingsScreen(remoteSettingsState.focusedIndex)
                ShellRoute.AnimeSources -> AnimeSourceManagementScreen(animeSourceSettings, animeSourceManagementState.focusedIndex)
                ShellRoute.AppManagement -> AppManagementScreen(state.apps, appManagementState.focusedIndex)
                ShellRoute.Media -> MediaLibraryScreen(mediaWebState) {
                    screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
                }
                is ShellRoute.Browser -> BrowserScreen(browserState) {
                    screen = if (animeOnly) ShellRoute.Anime else ShellRoute.Launcher
                }
            }
        }
        if (screen == ShellRoute.Launcher || (animeOnly && screen == ShellRoute.Anime && animeState.phase !in setOf(
                CrossPlatformAnimePhase.Playing,
                CrossPlatformAnimePhase.Buffering,
            ))) {
            Text(
                clockLabel,
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd)
                    .padding(top = 26.dp, end = 32.dp)
                    .tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 28f)
                    .padding(horizontal = 22.dp, vertical = 10.dp),
            )
        }
        if (controlCenterVisible) ControlCenter(controlCenterState)
            }
        }
    }
}

private data class ExternalMagnetPlayback(
    val candidate: AnimeStreamCandidate,
    val card: NativeMediaCard,
    val episode: AnimeEpisode,
)

private fun externalMagnetPlayback(rawMagnet: String): ExternalMagnetPlayback {
    val magnet = MagnetLink.normalize(rawMagnet)
    val title = MagnetLink.displayName(magnet)
    val id = TorrentIdentity.stableID(magnet)
    val candidate = AnimeStreamCandidate(
        url = magnet,
        quality = "Magnet · BT",
        headers = mapOf("resolver" to "torrent", "source" to "外部 Magnet"),
    )
    return ExternalMagnetPlayback(
        candidate = candidate,
        card = NativeMediaCard(
            id = "magnet-$id",
            title = title,
            subtitle = "外部 Magnet · BT 邊下邊播",
            thumbnailURL = "",
            playbackURL = magnet,
            animeSource = AnimeSourceKind.AniSubsBT,
            animeEpisodeNumber = 0,
        ),
        episode = AnimeEpisode("magnet:$id", title, 0, magnet),
    )
}

private fun playerWebCommand(command: RemoteCommand): RemoteCommand = when (command) {
    RemoteCommand.Select -> RemoteCommand.PlayPause
    RemoteCommand.Left -> RemoteCommand.Rewind
    RemoteCommand.Right -> RemoteCommand.FastForward
    RemoteCommand.Up -> RemoteCommand.VolumeUp
    RemoteCommand.Down -> RemoteCommand.VolumeDown
    else -> command
}

internal fun animePlaybackTimeLabel(seconds: Double): String {
    if (!seconds.isFinite()) return "0:00"
    val total = seconds.coerceAtLeast(0.0).toInt()
    return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
}

internal fun animePlayerProgress(currentSeconds: Double, durationSeconds: Double): Float {
    if (!currentSeconds.isFinite() || !durationSeconds.isFinite() || durationSeconds <= 0.0) return 0f
    return (currentSeconds / durationSeconds).toFloat().coerceIn(0f, 1f)
}

internal fun shouldHandleRootKeyEvent(hasExternalDispatcher: Boolean): Boolean = !hasExternalDispatcher

internal fun defaultShellApps(animeOnly: Boolean): List<ShellApp> = if (animeOnly) {
    listOf(ShellApp("anime", "動畫", "正版來源 · 訂閱 · 搜尋"))
} else {
    listOf(
        ShellApp("youtube", "YouTube", "官方影片"),
        ShellApp("bilibili", "Bilibili", "影片 · 動態 · 我的"),
        ShellApp("apple", "Apple", "Apple 官方網站", executable = "https://www.apple.com"),
        ShellApp("browser", "瀏覽器", "網頁瀏覽", executable = "https://duckduckgo.com"),
        ShellApp("video", "影片", "本機與網路影片"),
        ShellApp("anime", "動畫", "正版來源 · 訂閱 · 搜尋"),
        ShellApp("anime-sources", "動漫來源", "管理動畫來源"),
        ShellApp("remote", "遙控器", "按鍵與遙控器設定"),
        ShellApp("settings", "設定", "系統、播放與服務設定"),
        ShellApp("management", "管理", "安裝與管理 App"),
    )
}

@Composable
private fun NativeMediaRoute(
    title: String,
    tabs: List<String>,
    state: NativeMediaState,
    cards: List<NativeMediaCard>,
    status: String,
    webState: WebRuntimeState,
    onExitPlayer: () -> Unit,
) {
    if (state.phase == NativeMediaPhase.Player) {
        NativeMediaPlayer(title, cards.getOrNull(state.focusedCard), state, status, webState, onExitPlayer)
    } else {
        NativeMediaBrowser(title, tabs, state, cards, status)
    }
}

@Composable
private fun NativeMediaBrowser(
    title: String,
    tabs: List<String>,
    state: NativeMediaState,
    cards: List<NativeMediaCard>,
    status: String,
) {
    val listState = rememberLazyGridState()
    LaunchedEffect(state.focusedCard) {
        if (!state.isTopNavigationFocused && cards.isNotEmpty()) listState.animateScrollToItemCentered(state.focusedCard)
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Row(
                Modifier.clip(RoundedCornerShape(32.dp)).background(Color.Black.copy(alpha = .58f)).padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                tabs.forEachIndexed { index, tab ->
                    val focused = state.isTopNavigationFocused && state.focusedTab == index
                    Text(
                        tab,
                        color = if (focused) Color.Black else Color.White.copy(alpha = .68f),
                        fontSize = 23.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.clip(RoundedCornerShape(26.dp))
                            .background(if (focused) Color(0xFFF0F1F3) else Color.Transparent)
                            .padding(horizontal = 25.dp, vertical = 13.dp),
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(title, color = Color.White, fontSize = 48.sp, fontWeight = FontWeight.Bold)
            Text(status, color = Color.White.copy(alpha = .58f), fontSize = 21.sp, maxLines = 1)
        }
        if (cards.isEmpty()) {
            Box(
                Modifier.fillMaxWidth().weight(1f).tvShellSurface(TVSurfaceRole.Content, cornerRadius = 24f),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text("沒有影片", color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
                    Text(status, color = Color.White.copy(alpha = .58f), fontSize = 21.sp)
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(state.gridColumns),
                state = listState,
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                gridItemsIndexed(cards, key = { _, card -> card.id }) { index, card ->
                    MediaTile(card, !state.isTopNavigationFocused && state.focusedCard == index)
                }
            }
        }
        Text("方向鍵選影片，OK 播放，Menu 開啟控制中心，Back 或 Home 返回。", color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
    }
}

@Composable
private fun NativeMediaPlayer(
    service: String,
    card: NativeMediaCard?,
    state: NativeMediaState,
    status: String,
    webState: WebRuntimeState,
    onExitPlayer: () -> Unit,
) {
    val playbackCard = card ?: NativeMediaCard(
        id = "internal-player",
        title = service,
        subtitle = "內建播放器",
        thumbnailURL = "",
        playbackURL = webState.url,
    )
    val target = NativePlaybackTargetResolver.resolve(playbackCard)
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(service, color = Color.White.copy(alpha = .72f), fontSize = 28.sp, fontWeight = FontWeight.SemiBold)
        Box(
            Modifier.fillMaxWidth().height(760.dp)
                .tvShellSurface(TVSurfaceRole.Content, cornerRadius = 18f),
            contentAlignment = Alignment.Center,
        ) {
            when (target) {
                is NativePlaybackTarget.Direct -> PlatformAnimeVideoSurface(
                    candidate = target.candidate,
                    signal = webState.signal,
                    onExitRequested = onExitPlayer,
                    modifier = Modifier.fillMaxSize(),
                )
                is NativePlaybackTarget.Embedded -> PlatformWebSurface(
                    url = target.url,
                    signal = webState.signal,
                    onExitRequested = onExitPlayer,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Text(
                if (state.pendingSeekSeconds == 0) status else "已跳轉 ${if (state.pendingSeekSeconds > 0) "+" else ""}${state.pendingSeekSeconds} 秒",
                color = Color.White,
                fontSize = 18.sp,
                modifier = Modifier.align(Alignment.TopStart).padding(18.dp)
                    .background(Color.Black.copy(alpha = .56f), RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
        Text("OK 暫停／播放 · 左右快轉或倒轉 15 秒 · Back 返回影片列表", color = Color.White.copy(alpha = .68f), fontSize = 22.sp)
    }
}

@Composable
private fun MediaTile(card: NativeMediaCard, focused: Boolean) {
    val thumbnail = NetworkThumbnailRequest(card.thumbnailURL)
    Column(Modifier.fillMaxWidth().tvShellFocus(focused), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(16f / 9f)
                .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 16f),
            contentAlignment = Alignment.Center,
        ) {
            NetworkThumbnail(thumbnail, card.title, Modifier.fillMaxSize())
            if (!thumbnail.isLoadable) {
                Text("▶", color = if (focused) Color.Black else Color.White, fontSize = 40.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text(card.title, color = Color.White, fontSize = 23.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text(card.subtitle, color = Color.White.copy(alpha = .55f), fontSize = 18.sp, maxLines = 1)
    }
}

@Composable
private fun Launcher(state: LauncherState, history: List<NativeMediaCard>) {
    val listState = rememberLazyListState()
    val historyListState = rememberLazyListState()
    LaunchedEffect(state.focusedIndex) {
        if (state.focus == LauncherFocus.Apps && state.apps.isNotEmpty()) listState.animateScrollToItemCentered(state.focusedIndex)
    }
    LaunchedEffect(state.focusedHistoryIndex, state.focus) {
        if (state.focus == LauncherFocus.History && history.isNotEmpty()) historyListState.animateScrollToItemCentered(state.focusedHistoryIndex)
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
    ) {
        Spacer(Modifier.weight(1f))
        Text(
            state.focusedApp?.name ?: "TVShell",
            color = Color.White,
            fontSize = 30.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 30.dp, bottom = 16.dp),
        )
        Box(
            Modifier.fillMaxWidth()
                .tvShellSurface(TVSurfaceRole.Dock, cornerRadius = TVShellVisual.CornerRadius)
                .padding(horizontal = TVShellVisual.DockInset.dp, vertical = 26.dp),
        ) {
            LazyRow(
                state = listState,
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                itemsIndexed(state.apps, key = { _, app -> app.id }) { index, app ->
                    AppTile(app, state.focus == LauncherFocus.Apps && index == state.focusedIndex)
                }
            }
        }
        if (history.isNotEmpty()) {
            Text(
                "最近觀看",
                color = Color.White.copy(alpha = .78f),
                fontSize = 28.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = 34.dp, bottom = 16.dp),
            )
            LazyRow(
                state = historyListState,
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                itemsIndexed(history, key = { _, card -> card.id }) { index, card ->
                    HistoryTile(card, state.focus == LauncherFocus.History && index == state.focusedHistoryIndex)
                }
            }
        }
        Spacer(Modifier.height(34.dp))
        Text(state.status, color = Color.White.copy(alpha = .68f), fontSize = 22.sp)
    }
}

@Composable
private fun HistoryTile(card: NativeMediaCard, focused: Boolean) {
    Column(
        Modifier.width(340.dp).height(116.dp).tvShellFocus(focused)
            .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 14f)
            .padding(horizontal = 22.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            card.title,
            color = if (focused) Color.Black else Color.White,
            fontSize = 25.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
        )
        Text(
            card.subtitle,
            color = if (focused) Color.Black.copy(alpha = .58f) else Color.White.copy(alpha = .58f),
            fontSize = 18.sp,
            maxLines = 1,
        )
    }
}

@Composable
private fun AppTile(app: ShellApp, focused: Boolean) {
    Column(
        Modifier.width(222.dp).tvShellFocus(focused),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(width = 222.dp, height = 143.dp)
                .clip(RoundedCornerShape(TVShellVisual.AppIconCornerRadius.dp))
                .background(appAccent(app))
                .border(
                    width = if (focused) 3.dp else 1.dp,
                    color = Color.White.copy(alpha = if (focused) .72f else .10f),
                    shape = RoundedCornerShape(TVShellVisual.AppIconCornerRadius.dp),
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(appGlyph(app), color = Color.White, fontSize = 42.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(14.dp))
        Text(
            app.name,
            color = Color.White.copy(alpha = if (focused) 1f else 0f),
            fontSize = 25.sp,
            maxLines = 1,
        )
    }
}

private fun appGlyph(app: ShellApp): String = when (app.id) {
    "youtube" -> "▶"
    "bilibili" -> "b"
    "anime" -> "✦"
    "apple", "browser" -> "◉"
    "video" -> "▤"
    "anime-sources" -> "◆"
    "remote" -> "⌁"
    "settings" -> "⚙"
    "management" -> "☷"
    else -> app.name.take(2)
}

private fun appAccent(app: ShellApp): Color = when (app.id) {
    "youtube" -> Color(0xFFD92128)
    "bilibili" -> Color(0xFFEE5486)
    "anime" -> Color(0xFF6A43B8)
    "video" -> Color(0xFF1F75C9)
    "anime-sources" -> Color(0xFF168983)
    else -> Color(0xFF3A3E48)
}

@Composable
private fun RemoteSettingsScreen(focusedIndex: Int) {
    ReferenceSplitPage(
        glyph = "⌁",
        title = "遙控器設定",
        subtitle = "按鍵辨識、鍵盤與 Android TV 遙控器對照",
        rows = listOf(
            "方向鍵" to "↑ ↓ ← →",
            "OK／選擇" to "Enter／D-pad Center",
            "返回" to "Esc／Android Back",
            "Home" to "長按 Back／Home",
            "Menu／控制中心" to "Menu／F10",
            "播放／暫停" to "Space／Media Play Pause",
            "倒退／快轉" to "J／L 或媒體鍵",
            "音量" to "系統音量鍵",
        ),
        hint = "Windows 與 Android TV 使用固定、可預期的遙控器映射；Back 返回主畫面。",
        focusedIndex = focusedIndex,
    )
}

@Composable
private fun AnimeSourceManagementScreen(settings: AnimeSourceSettings, focusedIndex: Int) {
    ReferenceSplitPage(
        glyph = "◆",
        title = "動漫來源",
        subtitle = "管理解析來源、啟用狀態與訂閱網址",
        rows = listOf(
            "ani-subs CSS1" to "${if (settings.css1Enabled) "已啟用" else "已停用"} · ${settings.css1SubscriptionURL}",
            "動畫瘋" to "官方網站 · 保留廣告與登入",
            "YouTube" to "官方播放器",
            "Bilibili 番劇" to "官方來源與彈幕",
            "ani-subs BT" to "需要 RSS 設定",
            "Mikan" to "需要 RSS 設定",
            "動漫花園" to "需要 RSS 設定",
        ),
        hint = "CSS1 使用與 macOS 相同的內建網址；OK 啟用或停用，Menu 重設內建網址。",
        focusedIndex = focusedIndex,
    )
}

@Composable
private fun AppManagementScreen(apps: List<ShellApp>, focusedIndex: Int) {
    ReferenceSplitPage(
        glyph = "☷",
        title = "管理應用程式",
        subtitle = "查看內建與平台應用程式",
        rows = apps.map { it.name to it.subtitle },
        hint = "OK 開啟應用程式；平台應用程式由 Windows 開始功能表或 Android TV Launcher 自動發現。",
        focusedIndex = focusedIndex,
    )
}

@Composable
private fun MediaLibraryScreen(state: WebRuntimeState, onExitRequested: () -> Unit) {
    val target = NativePlaybackTargetResolver.resolve(
        NativeMediaCard(
            id = "media-library",
            title = "Big Buck Bunny",
            subtitle = "TVShell 內建播放器",
            thumbnailURL = "",
            playbackURL = state.url,
        ),
    )
    Column(Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("影片", color = Color.White, fontSize = 48.sp, fontWeight = FontWeight.Bold)
        Text("TVShell 內建播放器 · Big Buck Bunny", color = Color.White.copy(alpha = .58f), fontSize = 21.sp)
        when (target) {
            is NativePlaybackTarget.Direct -> PlatformAnimeVideoSurface(
                candidate = target.candidate,
                signal = state.signal,
                onExitRequested = onExitRequested,
                modifier = Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(18.dp)),
            )
            is NativePlaybackTarget.Embedded -> PlatformWebSurface(
                url = target.url,
                signal = state.signal,
                onExitRequested = onExitRequested,
                modifier = Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(18.dp)),
            )
        }
        Text("OK 暫停／播放，左右快轉，上下調整音量，Back 返回。", color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
    }
}

@Composable
private fun BrowserScreen(state: WebRuntimeState, onExitRequested: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        Text("瀏覽器", color = Color.White, fontSize = 48.sp, fontWeight = FontWeight.Bold)
        Text(state.url, color = Color.White.copy(alpha = .58f), fontSize = 21.sp, maxLines = 1)
        PlatformWebSurface(
            url = state.url,
            signal = state.signal,
            onExitRequested = onExitRequested,
            modifier = Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(18.dp)),
        )
        Text("方向鍵捲動，OK 選取，Back 返回。", color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
    }
}

@Composable
private fun ReferenceSplitPage(
    glyph: String,
    title: String,
    subtitle: String,
    rows: List<Pair<String, String>>,
    hint: String,
    focusedIndex: Int = 0,
) {
    val listState = rememberLazyListState()
    LaunchedEffect(focusedIndex, rows.size) {
        if (rows.isNotEmpty()) listState.animateScrollToItemCentered(focusedIndex.coerceIn(rows.indices))
    }
    Row(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 60.dp),
        horizontalArrangement = Arrangement.spacedBy(64.dp),
    ) {
        Column(Modifier.width(500.dp).fillMaxHeight(), verticalArrangement = Arrangement.Center) {
            Text(glyph, color = Color.White.copy(alpha = .62f), fontSize = 150.sp, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(28.dp))
            Text(title, color = Color.White, fontSize = 52.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            Text(subtitle, color = Color.White.copy(alpha = .58f), fontSize = 24.sp)
        }
        Column(Modifier.weight(1f).fillMaxHeight()) {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                itemsIndexed(rows) { index, row ->
                Row(
                    Modifier.fillMaxWidth().tvShellSurface(TVSurfaceRole.Panel, isFocused = index == focusedIndex, cornerRadius = 10f)
                        .padding(horizontal = 24.dp, vertical = 19.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(row.first, color = if (index == focusedIndex) Color.Black else Color.White, fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
                    Text(row.second, color = if (index == focusedIndex) Color.Black.copy(alpha = .62f) else Color.White.copy(alpha = .58f), fontSize = 20.sp, maxLines = 1)
                }
            }
            }
            Spacer(Modifier.height(18.dp))
            Text(hint, color = Color.White.copy(alpha = .58f), fontSize = 20.sp)
        }
    }
}

@Composable
private fun SettingsScreen(state: SettingsState) {
    val listState = rememberLazyListState()
    LaunchedEffect(state.focusedItem) {
        listState.animateScrollToItemCentered(state.focusedItem.ordinal)
    }
    Row(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 60.dp),
        horizontalArrangement = Arrangement.spacedBy(64.dp),
    ) {
        Column(
            Modifier.width(500.dp).fillMaxHeight(),
            verticalArrangement = Arrangement.Center,
        ) {
            Text("⚙", color = Color.White.copy(alpha = .62f), fontSize = 150.sp, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(28.dp))
            Text("設定", color = Color.White, fontSize = 52.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            Text("系統、播放、彈幕與服務設定", color = Color.White.copy(alpha = .58f), fontSize = 24.sp)
        }
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxHeight(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            itemsIndexed(SettingsItem.entries) { index, item ->
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    settingsSectionTitle(index)?.let { title ->
                        Text(
                            title,
                            color = Color.White.copy(alpha = .64f),
                            fontSize = 29.sp,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = 14.dp),
                        )
                    }
                    SettingsRow(item, state, item == state.focusedItem)
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 8.dp, bottom = 48.dp)) {
                    ServiceStatusRow("▶", "YouTube", configured = false)
                    ServiceStatusRow("彈", "彈幕", configured = false)
                    ServiceStatusRow("b", "Bilibili", configured = false)
                }
            }
        }
    }
}

@Composable
private fun SettingsRow(item: SettingsItem, state: SettingsState, focused: Boolean) {
    Row(
        Modifier.fillMaxWidth().height(76.dp).tvShellFocus(focused)
            .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 10f)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        val foreground = if (focused) Color.Black else Color.White
        Text(settingsGlyph(item), color = foreground, fontSize = 25.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(38.dp))
        Text(settingsTitle(item), color = foreground, fontSize = 27.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Text(settingsValue(item, state), color = foreground.copy(alpha = if (focused) .66f else .54f), fontSize = 25.sp, maxLines = 1)
        Text(if (item.isAdjustable) "‹  ›" else "›", color = foreground, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ServiceStatusRow(glyph: String, title: String, configured: Boolean) {
    Row(
        Modifier.fillMaxWidth().height(72.dp)
            .tvShellSurface(TVSurfaceRole.Content, cornerRadius = 20f)
            .padding(horizontal = 28.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(glyph, color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(44.dp))
        Text(title, color = Color.White, fontSize = 25.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        Text("●", color = if (configured) Color(0xFF5DD879) else Color(0xFFFFA43A), fontSize = 14.sp)
        Text(if (configured) "已連線" else "需要設定", color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
    }
}

private fun settingsSectionTitle(index: Int): String? = when (index) {
    0 -> "外觀"
    2 -> "播放與網頁"
    4 -> "彈幕"
    8 -> "服務與帳戶"
    else -> null
}

private fun settingsTitle(item: SettingsItem): String = when (item) {
    SettingsItem.Scale -> "介面縮放"
    SettingsItem.Wallpaper -> "壁紙"
    SettingsItem.WebZoom -> "網頁放大"
    SettingsItem.VideoSource -> "影片位置"
    SettingsItem.DanmakuSize -> "彈幕大小"
    SettingsItem.DanmakuSpeed -> "彈幕速度"
    SettingsItem.DanmakuOpacity -> "彈幕透明度"
    SettingsItem.DanmakuDensity -> "彈幕密度"
    SettingsItem.Credentials -> "憑證與服務"
}

private fun settingsValue(item: SettingsItem, state: SettingsState): String = when (item) {
    SettingsItem.Scale -> state.preferences.displayScaleLabel
    SettingsItem.Wallpaper -> state.preferences.wallpaperLabel
    SettingsItem.WebZoom -> "${(state.preferences.webZoom * 100).toInt()}%"
    SettingsItem.VideoSource -> state.videoSourceLabel
    SettingsItem.DanmakuSize -> state.preferences.danmaku.sizeLabel
    SettingsItem.DanmakuSpeed -> state.preferences.danmaku.speedLabel
    SettingsItem.DanmakuOpacity -> state.preferences.danmaku.opacityLabel
    SettingsItem.DanmakuDensity -> state.preferences.danmaku.densityLabel
    SettingsItem.Credentials -> "${state.credentialsSummary} · ${state.credentialsLocation}"
}

private fun settingsGlyph(item: SettingsItem): String = when (item) {
    SettingsItem.Scale -> "▦"
    SettingsItem.Wallpaper -> "▧"
    SettingsItem.WebZoom -> "◎"
    SettingsItem.VideoSource -> "▶"
    SettingsItem.DanmakuSize -> "A"
    SettingsItem.DanmakuSpeed -> "»"
    SettingsItem.DanmakuOpacity -> "◐"
    SettingsItem.DanmakuDensity -> "≡"
    SettingsItem.Credentials -> "⚿"
}

@Composable
private fun AnimeBrowser(
    state: CrossPlatformAnimeBrowserState,
    cards: List<NativeMediaCard>,
    history: List<NativeMediaCard>,
    episodes: List<AnimeEpisode>,
    status: String,
    danmaku: List<DanmakuComment>,
    danmakuStatus: String,
    playbackSeconds: Double,
    playbackDurationSeconds: Double,
    danmakuSettings: DanmakuSettings,
    webState: WebRuntimeState,
    torrentSnapshot: TorrentTransferSnapshot,
) {
    val sources = animeSourcesFor(state.focusedTopTab)
    val visibleCards = if (state.focusedTopTab == AnimeTopTab.History) history else cards
    val selectedCard = visibleCards.getOrNull(state.selectedCardIndex)
    if (state.phase == CrossPlatformAnimePhase.Details) {
        AnimeDetailScreen(selectedCard, status)
        return
    }
    if (state.phase == CrossPlatformAnimePhase.EpisodeLoading) {
        AnimeProgressScreen("正在載入選集", status)
        return
    }
    if (state.phase == CrossPlatformAnimePhase.Episodes || state.phase == CrossPlatformAnimePhase.Resolving) {
        Box(Modifier.fillMaxSize()) {
            AnimeEpisodeScreen(selectedCard, episodes, state, status)
            if (state.phase == CrossPlatformAnimePhase.Resolving && !state.isStreamPickerVisible) {
                AnimeProgressOverlay("正在解析播放源", status)
            }
            if (state.isStreamPickerVisible) AnimeStreamPicker(state, episodes.getOrNull(state.focusedEpisode))
            if (state.downloadManager.isVisible) TorrentDownloadManagerOverlay(state)
        }
        return
    }
    if (state.phase == CrossPlatformAnimePhase.Buffering) {
        Box(Modifier.fillMaxSize()) {
            AnimeTorrentBufferingScreen(
                selectedCard,
                episodes.getOrNull(state.focusedEpisode),
                torrentSnapshot,
                status,
            )
            if (state.isStreamPickerVisible) AnimeStreamPicker(state, episodes.getOrNull(state.focusedEpisode))
        }
        return
    }
    if (state.phase == CrossPlatformAnimePhase.Playing) {
        Box(Modifier.fillMaxSize()) {
            AnimePlayerScreen(
                selectedCard,
                episodes.getOrNull(state.focusedEpisode),
                state,
                status,
                danmaku,
                danmakuStatus,
                playbackSeconds,
                playbackDurationSeconds,
                danmakuSettings,
                webState,
                torrentSnapshot,
            )
            if (state.isStreamPickerVisible) AnimeStreamPicker(state, episodes.getOrNull(state.focusedEpisode))
        }
        return
    }
    val sourceListState = rememberLazyListState()
    val titleGridState = rememberLazyGridState()
    LaunchedEffect(state.focusedSource, state.focusedCard, state.phase) {
        if (state.phase == CrossPlatformAnimePhase.Titles && visibleCards.isNotEmpty()) {
            titleGridState.animateScrollToItemCentered(state.focusedCard)
        } else if (sources.isNotEmpty()) {
            sourceListState.animateScrollToItemCentered(state.focusedSource)
        }
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Row(
                Modifier.clip(RoundedCornerShape(32.dp)).background(Color.Black.copy(alpha = .55f)).padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                AnimeTopTab.entries.forEach { tab ->
                    val selected = state.focusedTopTab == tab
                    val focused = selected && state.isTopNavigationFocused
                    Text(
                        tab.title,
                        color = if (focused) Color.Black else Color.White.copy(alpha = if (selected) .92f else .58f),
                        fontSize = 23.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier
                            .clip(RoundedCornerShape(26.dp))
                            .background(if (focused) Color(0xFFF0F1F3) else Color.Transparent)
                            .padding(horizontal = 25.dp, vertical = 13.dp),
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("動畫", color = Color.White, fontSize = 48.sp, fontWeight = FontWeight.Bold)
            Text(status, color = Color.White.copy(alpha = .58f), fontSize = 21.sp, maxLines = 1)
        }
        if (state.phase == CrossPlatformAnimePhase.Titles && visibleCards.isNotEmpty()) {
            LazyVerticalGrid(
                columns = GridCells.Fixed(state.activeTitleGridColumns),
                state = titleGridState,
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalArrangement = Arrangement.spacedBy(32.dp),
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                gridItemsIndexed(visibleCards, key = { _, card -> card.id }) { index, card ->
                    AnimeTitleTile(card, !state.isTopNavigationFocused && index == state.focusedCard)
                }
            }
        } else if (state.phase == CrossPlatformAnimePhase.Titles) {
            AnimeEmptyState(
                if (state.focusedTopTab == AnimeTopTab.History) "沒有觀看記錄" else "沒有動畫",
                if (state.focusedTopTab == AnimeTopTab.History) "播放過的動畫會顯示在這裡。" else status,
            )
        } else if (state.phase == CrossPlatformAnimePhase.Loading) {
            AnimeEmptyState("正在載入", status)
        } else if (sources.isEmpty()) {
            AnimeEmptyState(
                if (state.focusedTopTab == AnimeTopTab.History) "沒有觀看記錄" else "搜尋動畫",
                if (state.focusedTopTab == AnimeTopTab.History) "播放過的動畫會顯示在這裡。" else "按 Menu 開啟虛擬鍵盤搜尋動漫。",
            )
        } else {
            LazyRow(
                state = sourceListState,
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                itemsIndexed(sources, key = { _, source -> "${source.tab}:${source.kind}" }) { index, source ->
                    AnimeSourceTile(source, !state.isTopNavigationFocused && index == state.focusedSource)
                }
            }
        }
        Text(
            "方向鍵選作品，OK 開啟，Menu 開啟控制中心，Back 返回。",
            color = Color.White.copy(alpha = .62f),
            fontSize = 22.sp,
        )
    }
}

@Composable
private fun AnimeDetailScreen(card: NativeMediaCard?, status: String) {
    Row(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 68.dp),
        horizontalArrangement = Arrangement.spacedBy(48.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.width(280.dp).aspectRatio(2f / 3f)
                .tvShellSurface(TVSurfaceRole.Content, cornerRadius = 12f),
            contentAlignment = Alignment.Center,
        ) {
            card?.let { NetworkThumbnail(NetworkThumbnailRequest(it.thumbnailURL), it.title, Modifier.fillMaxSize()) }
            if (card?.thumbnailURL.isNullOrBlank()) Text("動畫", color = Color.White.copy(alpha = .7f), fontSize = 48.sp, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Text(card?.subtitle ?: "動畫", color = Color.White.copy(alpha = .62f), fontSize = 24.sp, fontWeight = FontWeight.SemiBold)
            Text(card?.title ?: "動漫詳情", color = Color.White, fontSize = 56.sp, fontWeight = FontWeight.Bold, maxLines = 3)
            Text(status, color = Color.White.copy(alpha = .62f), fontSize = 22.sp, maxLines = 4)
            Text(
                "開始觀看",
                color = Color.Black,
                fontSize = 31.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.tvShellSurface(TVSurfaceRole.Content, isFocused = true, cornerRadius = 10f)
                    .padding(horizontal = 34.dp, vertical = 20.dp),
            )
            Text("OK 載入選集，Back 回封面牆。", color = Color.White.copy(alpha = .58f), fontSize = 21.sp)
        }
    }
}

@Composable
private fun AnimeProgressScreen(title: String, status: String) {
    Box(Modifier.fillMaxSize().padding(86.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(title, color = Color.White, fontSize = 42.sp, fontWeight = FontWeight.Bold)
            Text(status, color = Color.White.copy(alpha = .62f), fontSize = 23.sp)
        }
    }
}

@Composable
private fun AnimeEpisodeScreen(
    card: NativeMediaCard?,
    episodes: List<AnimeEpisode>,
    state: CrossPlatformAnimeBrowserState,
    status: String,
) {
    val listState = rememberLazyGridState()
    LaunchedEffect(state.focusedEpisode) {
        if (episodes.isNotEmpty()) listState.animateScrollToItemCentered(state.focusedEpisode)
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 54.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Text(card?.title ?: "選集", color = Color.White, fontSize = 64.sp, fontWeight = FontWeight.Bold, maxLines = 2)
        Text(status, color = Color.White.copy(alpha = .62f), fontSize = 24.sp, maxLines = 2)
        LazyVerticalGrid(
            columns = GridCells.Fixed(state.episodeGridColumns),
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(22.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
            modifier = Modifier.fillMaxWidth().weight(1f),
        ) {
            gridItemsIndexed(episodes, key = { _, episode -> episode.id }) { index, episode ->
                val focused = index == state.focusedEpisode && state.phase == CrossPlatformAnimePhase.Episodes
                Column(
                    Modifier.height(158.dp).tvShellFocus(focused)
                        .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 10f)
                        .padding(26.dp),
                    verticalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(if (episode.number > 0) episode.number.toString().padStart(2, '0') else "BT", color = if (focused) Color.Black.copy(alpha = .62f) else Color.White.copy(alpha = .62f), fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    Text(episode.title, color = if (focused) Color.Black else Color.White, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                }
            }
        }
        Text("方向鍵選集，OK 解析播放源，Menu 管理下載，Back 回詳情。", color = Color.White.copy(alpha = .6f), fontSize = 21.sp)
    }
}

@Composable
private fun AnimePlayerScreen(
    card: NativeMediaCard?,
    episode: AnimeEpisode?,
    state: CrossPlatformAnimeBrowserState,
    status: String,
    danmaku: List<DanmakuComment>,
    danmakuStatus: String,
    playbackSeconds: Double,
    playbackDurationSeconds: Double,
    danmakuSettings: DanmakuSettings,
    webState: WebRuntimeState,
    torrentSnapshot: TorrentTransferSnapshot,
) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val candidate = state.activePlayerCandidate
        if (candidate?.headers?.get("resolver") == "official") {
            PlatformWebSurface(
                url = candidate.url,
                signal = webState.signal,
                onExitRequested = {},
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            PlatformAnimeVideoSurface(
                candidate = candidate,
                signal = webState.signal,
                onExitRequested = {},
                modifier = Modifier.fillMaxSize(),
            )
        }
        if (danmakuSettings.isVisible && danmaku.isNotEmpty()) {
            DanmakuOverlay(danmaku, playbackSeconds, danmakuSettings)
        }
        if (state.isPlayerHUDVisible) {
            Column(
                Modifier.align(Alignment.BottomStart).fillMaxWidth()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Color.Black.copy(alpha = .92f)),
                        ),
                    )
                    .padding(horizontal = 62.dp, vertical = 36.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text(
                    if (state.activeTorrentGeneration != null && torrentSnapshot.selectedBytes > 0) {
                        "BT：已下載 ${TorrentTransferSnapshot.formatBytes(torrentSnapshot.selectedBytes)} · ${episode?.title ?: "正在播放"}"
                    } else {
                        episode?.title ?: "正在播放"
                    },
                    color = Color.White.copy(alpha = .72f),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
                Text(card?.title ?: "動畫", color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(Color.White.copy(alpha = .28f))) {
                    Box(
                        Modifier.fillMaxWidth(animePlayerProgress(playbackSeconds, playbackDurationSeconds))
                            .fillMaxHeight().background(Color.White),
                    )
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(animePlaybackTimeLabel(playbackSeconds), color = Color.White.copy(alpha = .64f), fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        if (playbackDurationSeconds > 0.0) "-${animePlaybackTimeLabel((playbackDurationSeconds - playbackSeconds).coerceAtLeast(0.0))}" else "--:--",
                        color = Color.White.copy(alpha = .64f),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(if (state.isPlaying) "▶ 播放中" else "Ⅱ 已暫停", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Text(
                        if (state.activeTorrentGeneration != null && torrentSnapshot.detailText.isNotBlank()) torrentSnapshot.detailText else status,
                        color = Color.White.copy(alpha = .68f),
                        fontSize = 19.sp,
                        maxLines = 1,
                    )
                }
            }
            Text(
                "${if (danmakuSettings.isVisible) "彈幕 ON" else "彈幕 OFF"}  ·  $danmakuStatus",
                color = Color.White,
                fontSize = 19.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(34.dp)
                    .tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 10f)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            )
        }
    }
}

@Composable
private fun AnimeTorrentBufferingScreen(
    card: NativeMediaCard?,
    episode: AnimeEpisode?,
    snapshot: TorrentTransferSnapshot,
    status: String,
) {
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        Column(
            Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = .94f))))
                .padding(horizontal = 72.dp, vertical = 54.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text("BT 邊下邊播 · ${episode?.title ?: "正在準備"}", color = Color.White.copy(alpha = .68f), fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
            Text(card?.title ?: "動畫", color = Color.White, fontSize = 44.sp, fontWeight = FontWeight.Bold, maxLines = 2)
            Text(snapshot.statusText.takeUnless { snapshot.phase == TorrentTransferPhase.Idle } ?: status, color = Color.White.copy(alpha = .82f), fontSize = 23.sp)
            Box(Modifier.fillMaxWidth().height(7.dp).clip(RoundedCornerShape(4.dp)).background(Color.White.copy(alpha = .24f))) {
                Box(Modifier.fillMaxWidth(snapshot.progressFraction).fillMaxHeight().background(Color.White))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(snapshot.selectedPath ?: "正在取得種子資訊", color = Color.White.copy(alpha = .64f), fontSize = 19.sp, maxLines = 1)
                Text(snapshot.detailText, color = Color.White.copy(alpha = .64f), fontSize = 19.sp, maxLines = 1)
            }
            Text("Back 返回選集並保留背景下載", color = Color.White.copy(alpha = .5f), fontSize = 18.sp)
        }
    }
}

@Composable
private fun TorrentDownloadManagerOverlay(state: CrossPlatformAnimeBrowserState) {
    val manager = state.downloadManager
    val listState = rememberLazyListState()
    LaunchedEffect(manager.focusedIndex, manager.items.size) {
        if (manager.items.isNotEmpty()) listState.animateScrollToItemCentered(manager.focusedIndex)
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .45f)), contentAlignment = Alignment.Center) {
        Column(
            Modifier.width(980.dp).height(760.dp)
                .tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 20f)
                .padding(38.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text("BT 下載管理", color = Color.White, fontSize = 42.sp, fontWeight = FontWeight.Bold)
            Text("方向鍵選擇，OK 或 Menu 刪除，Back 關閉。", color = Color.White.copy(alpha = .58f), fontSize = 20.sp)
            if (manager.items.isEmpty()) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    Text("目前沒有 BT 快取", color = Color.White.copy(alpha = .56f), fontSize = 26.sp)
                }
            } else {
                LazyColumn(
                    state = listState,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                    modifier = Modifier.fillMaxWidth().weight(1f),
                ) {
                    itemsIndexed(manager.items, key = { _, item -> item.id }) { index, item ->
                        val focused = index == manager.focusedIndex
                        Row(
                            Modifier.fillMaxWidth().tvShellFocus(focused)
                                .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 12f)
                                .padding(horizontal = 24.dp, vertical = 20.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                Text(item.title, color = if (focused) Color.Black else Color.White, fontSize = 25.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                                Text(item.subtitle, color = if (focused) Color.Black.copy(alpha = .6f) else Color.White.copy(alpha = .58f), fontSize = 19.sp, maxLines = 1)
                            }
                            Text(TorrentTransferSnapshot.formatBytes(item.bytes), color = if (focused) Color.Black.copy(alpha = .68f) else Color.White.copy(alpha = .64f), fontSize = 21.sp, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DanmakuOverlay(
    comments: List<DanmakuComment>,
    currentTime: Double,
    settings: DanmakuSettings,
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val viewportWidth = maxWidth.value
        val fontSize = 30f * settings.sizeScale
        val estimatedWidth = 420f * settings.sizeScale
        val active = DanmakuTimeline.active(comments, currentTime, viewportWidth, estimatedWidth, settings.speedScale)
        active.forEach { comment ->
            val textWidth = (comment.text.length * fontSize * .9f + 44f).coerceAtLeast(120f)
            val age = (currentTime - comment.time).coerceAtLeast(0.0)
            val x = DanmakuMotion.horizontalOffset(age, viewportWidth, textWidth, settings.speedScale)
            val lane = DanmakuMotion.laneIndex("${comment.time}-${comment.text}", settings.density)
            Text(
                comment.text,
                color = danmakuColor(comment.colorHex).copy(alpha = settings.opacity),
                fontSize = fontSize.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                modifier = Modifier.offset(x = x.dp, y = (52f + lane * (fontSize + 16f)).dp)
                    .background(Color.Black.copy(alpha = .24f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            )
        }
    }
}

private suspend fun LazyListState.animateScrollToItemCentered(index: Int) {
    animateScrollToItem(index)
    val item = layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return
    val viewportCenter = (layoutInfo.viewportStartOffset + layoutInfo.viewportEndOffset) / 2
    val itemCenter = item.offset + item.size / 2
    animateScrollBy((itemCenter - viewportCenter).toFloat())
}

private suspend fun LazyGridState.animateScrollToItemCentered(index: Int) {
    animateScrollToItem(index)
    val item = layoutInfo.visibleItemsInfo.firstOrNull { it.index == index } ?: return
    val viewportCenter = (layoutInfo.viewportStartOffset + layoutInfo.viewportEndOffset) / 2
    val itemCenter = item.offset.y + item.size.height / 2
    animateScrollBy((itemCenter - viewportCenter).toFloat())
}

private fun danmakuColor(value: String): Color {
    val number = value.removePrefix("#").toIntOrNull(16) ?: 0xFFFFFF
    return Color(
        red = ((number shr 16) and 0xFF) / 255f,
        green = ((number shr 8) and 0xFF) / 255f,
        blue = (number and 0xFF) / 255f,
        alpha = 1f,
    )
}

@Composable
private fun AnimeProgressOverlay(title: String, status: String) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .58f)), contentAlignment = Alignment.Center) {
        Column(
            Modifier.width(620.dp).tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 20f).padding(38.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            Text(status, color = Color.White.copy(alpha = .62f), fontSize = 20.sp)
        }
    }
}

@Composable
private fun AnimeStreamPicker(state: CrossPlatformAnimeBrowserState, episode: AnimeEpisode?) {
    val listState = rememberLazyListState()
    LaunchedEffect(state.focusedStreamIndex, state.streamCandidates.size) {
        if (state.streamCandidates.isNotEmpty()) listState.animateScrollToItemCentered(state.focusedStreamIndex)
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .58f)), contentAlignment = Alignment.Center) {
        Column(
            Modifier.width(1120.dp).height(760.dp).tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 20f).padding(34.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("選擇播放源", color = Color.White, fontSize = 38.sp, fontWeight = FontWeight.Bold)
            Text(episode?.title ?: "目前集數", color = Color.White.copy(alpha = .62f), fontSize = 21.sp)
            LazyColumn(
                state = listState,
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                itemsIndexed(state.streamCandidates, key = { _, candidate -> candidate.url }) { index, candidate ->
                    val focused = index == state.focusedStreamIndex
                    Row(
                        Modifier.fillMaxWidth().tvShellFocus(focused)
                            .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 10f)
                            .padding(horizontal = 24.dp, vertical = 20.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Text(candidate.headers["title"] ?: "播放線 ${index + 1}", color = if (focused) Color.Black else Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold, maxLines = 2)
                            Text(candidate.headers["channel"] ?: candidate.headers["source"] ?: candidate.url.substringAfter("//").substringBefore('/'), color = if (focused) Color.Black.copy(alpha = .56f) else Color.White.copy(alpha = .52f), fontSize = 17.sp, maxLines = 1)
                        }
                        Text(candidate.quality, color = if (focused) Color.Black.copy(alpha = .64f) else Color.White.copy(alpha = .62f), fontSize = 21.sp)
                    }
                }
            }
            Text("方向鍵選擇，OK 播放，Back 取消。", color = Color.White.copy(alpha = .56f), fontSize = 19.sp)
        }
    }
}

@Composable
private fun AnimeTitleTile(card: NativeMediaCard, focused: Boolean) {
    Column(
        Modifier.tvShellFocus(focused),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().aspectRatio(2f / 3f)
                .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 12f),
            contentAlignment = Alignment.Center,
        ) {
            if (card.thumbnailURL.isNotBlank()) {
                NetworkThumbnail(NetworkThumbnailRequest(card.thumbnailURL), card.title, Modifier.fillMaxSize())
            } else {
                Text("動畫", color = if (focused) Color.Black.copy(alpha = .62f) else Color.White.copy(alpha = .62f), fontSize = 32.sp, fontWeight = FontWeight.Bold)
            }
        }
        Text(card.title, color = Color.White, fontSize = 23.sp, fontWeight = FontWeight.Bold, maxLines = 2)
        Text(card.subtitle, color = Color.White.copy(alpha = .56f), fontSize = 17.sp, maxLines = 1)
    }
}

@Composable
private fun ColumnScope.AnimeEmptyState(title: String, message: String) {
    Box(
        Modifier.fillMaxWidth().weight(1f).tvShellSurface(TVSurfaceRole.Content, cornerRadius = 24f),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(title, color = Color.White, fontSize = 34.sp, fontWeight = FontWeight.Bold)
            Text(message, color = Color.White.copy(alpha = .58f), fontSize = 21.sp)
        }
    }
}

@Composable
private fun AnimeSourceTile(source: AnimeSourceDefinition, focused: Boolean) {
    Column(
        Modifier.width(330.dp).tvShellFocus(focused),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.fillMaxWidth().height(186.dp)
                .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 18f)
                .padding(24.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(animeSourceGlyph(source.kind), color = if (focused) Color.Black else Color.White, fontSize = 38.sp, fontWeight = FontWeight.Bold)
                Text(source.title, color = if (focused) Color.Black else Color.White, fontSize = 27.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                Text(source.subtitle, color = if (focused) Color.Black.copy(alpha = .62f) else Color.White.copy(alpha = .58f), fontSize = 18.sp, maxLines = 1)
            }
        }
    }
}

private fun animeSourceGlyph(kind: AnimeSourceKind): String = when (kind) {
    AnimeSourceKind.Bilibili -> "Bi"
    AnimeSourceKind.BangumiYouTube -> "BG"
    AnimeSourceKind.AniGamer -> "15+"
    AnimeSourceKind.YouTube -> "▶"
    AnimeSourceKind.CSS1 -> "CSS"
    AnimeSourceKind.AniSubsBT -> "BT"
    AnimeSourceKind.Mikan -> "蜜"
    AnimeSourceKind.DMHY -> "花"
}

@Composable
private fun ControlCenter(state: ControlCenterState) {
    val gridState = rememberLazyGridState()
    LaunchedEffect(state.focusedItem) {
        gridState.animateScrollToItemCentered(state.focusedItem.ordinal)
    }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .18f)), contentAlignment = Alignment.TopEnd) {
        Column(
            Modifier.width(560.dp).fillMaxHeight().padding(top = 26.dp, end = 26.dp, bottom = 26.dp)
                .tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 24f)
                .padding(28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("控制中心", color = Color.White, fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    Text("TVShell", color = Color.White.copy(alpha = .62f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
                Text("●", color = Color.White.copy(alpha = .9f), fontSize = 34.sp)
            }
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                state = gridState,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.weight(1f).fillMaxWidth(),
            ) {
                gridItemsIndexed(ControlCenterItem.entries) { _, item ->
                    ControlCenterTile(item, state, item == state.focusedItem)
                }
            }
            Text(
                "方向鍵移動，OK 調整，左右可調整音量，Menu 或 Back 關閉",
                color = Color.White.copy(alpha = .58f),
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun ControlCenterTile(item: ControlCenterItem, state: ControlCenterState, focused: Boolean) {
    Column(
        Modifier.height(128.dp).tvShellFocus(focused)
            .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 12f)
            .padding(18.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(controlCenterGlyph(item), color = if (focused) Color.Black else Color.White.copy(alpha = .92f), fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(controlCenterTitle(item), color = if (focused) Color.Black else Color.White.copy(alpha = .92f), fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(controlCenterValue(item, state), color = if (focused) Color.Black.copy(alpha = .66f) else Color.White.copy(alpha = .68f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

private fun controlCenterTitle(item: ControlCenterItem): String = when (item) {
    ControlCenterItem.Home -> "主畫面"
    ControlCenterItem.FocusMode -> "勿擾模式"
    ControlCenterItem.Audio -> "音量"
    ControlCenterItem.Display -> "顯示縮放"
    ControlCenterItem.Wallpaper -> "壁紙"
    ControlCenterItem.WebZoom -> "網頁放大"
    ControlCenterItem.Remote -> "網路遙控器"
    ControlCenterItem.Settings -> "設定"
    ControlCenterItem.DanmakuVisibility -> "彈幕顯示"
    ControlCenterItem.DanmakuSize -> "彈幕大小"
    ControlCenterItem.DanmakuSpeed -> "彈幕速度"
    ControlCenterItem.DanmakuOpacity -> "彈幕透明度"
    ControlCenterItem.DanmakuDensity -> "彈幕密度"
}

private fun controlCenterValue(item: ControlCenterItem, state: ControlCenterState): String = when (item) {
    ControlCenterItem.Home -> "TVShell"
    ControlCenterItem.FocusMode -> if (state.isFocusModeEnabled) "開啟" else "關閉"
    ControlCenterItem.Audio -> if (state.isMuted) "靜音" else "${(state.volume * 100).toInt()}%"
    ControlCenterItem.Display -> state.displayScaleLabel
    ControlCenterItem.Wallpaper -> state.wallpaperLabel
    ControlCenterItem.WebZoom -> "${(state.webZoom * 100).toInt()}%"
    ControlCenterItem.Remote -> if (state.isRemoteRunning) "已啟動" else "啟動"
    ControlCenterItem.Settings -> "更多選項"
    ControlCenterItem.DanmakuVisibility -> if (state.danmaku.isVisible) "顯示" else "隱藏"
    ControlCenterItem.DanmakuSize -> state.danmaku.sizeLabel
    ControlCenterItem.DanmakuSpeed -> state.danmaku.speedLabel
    ControlCenterItem.DanmakuOpacity -> state.danmaku.opacityLabel
    ControlCenterItem.DanmakuDensity -> state.danmaku.densityLabel
}

private fun controlCenterGlyph(item: ControlCenterItem): String = when (item) {
    ControlCenterItem.Home -> "⌂"
    ControlCenterItem.FocusMode -> "☾"
    ControlCenterItem.Audio -> "◖"
    ControlCenterItem.Display -> "▣"
    ControlCenterItem.Wallpaper -> "▧"
    ControlCenterItem.WebZoom -> "Aa"
    ControlCenterItem.Remote -> "⌁"
    ControlCenterItem.Settings -> "⚙"
    ControlCenterItem.DanmakuVisibility -> "彈"
    ControlCenterItem.DanmakuSize -> "A"
    ControlCenterItem.DanmakuSpeed -> "»"
    ControlCenterItem.DanmakuOpacity -> "◐"
    ControlCenterItem.DanmakuDensity -> "≡"
}

fun desktopKeyToRemoteCommand(key: Key, isShiftPressed: Boolean): RemoteCommand? = when {
    key == Key.F10 && isShiftPressed -> RemoteCommand.Menu
    key == Key.F10 -> RemoteCommand.Menu
    else -> key.toBaseRemoteCommand()
}

private fun Key.toBaseRemoteCommand(): RemoteCommand? = when (this) {
    Key.DirectionUp -> RemoteCommand.Up
    Key.DirectionDown -> RemoteCommand.Down
    Key.DirectionLeft -> RemoteCommand.Left
    Key.DirectionRight -> RemoteCommand.Right
    Key.Enter, Key.NumPadEnter, Key.DirectionCenter -> RemoteCommand.Select
    Key.Escape, Key.Back -> RemoteCommand.Back
    Key.Menu -> RemoteCommand.Menu
    Key.MediaPlayPause, Key.Spacebar -> RemoteCommand.PlayPause
    else -> null
}
