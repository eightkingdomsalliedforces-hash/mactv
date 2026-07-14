package dev.tvshell.shared

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun TVShellApp(
    adapter: PlatformAdapter,
    animeOnly: Boolean = false,
    appsRevision: Int = 0,
    dispatcher: RemoteCommandDispatcher? = null,
) {
    val discovered = remember(appsRevision) { adapter.installedApps() }
    val builtIns = remember {
        if (animeOnly) listOf(ShellApp("anime", "動畫", "正版來源 · 訂閱 · 搜尋"))
        else listOf(
            ShellApp("youtube", "YouTube", "官方影片"),
            ShellApp("bilibili", "Bilibili", "影片 · 動態 · 我的"),
            ShellApp("anime", "動畫", "正版來源 · 訂閱 · 搜尋"),
        )
    }
    var state by remember(discovered) { mutableStateOf(LauncherState((builtIns + discovered).distinctBy { it.id })) }
    var screen by remember { mutableStateOf(if (animeOnly) ShellScreen.Anime else ShellScreen.Launcher) }
    var animeState by remember { mutableStateOf(CrossPlatformAnimeBrowserState(sourceCount = 2)) }
    var animeCards by remember { mutableStateOf(emptyList<NativeMediaCard>()) }
    var animeStatus by remember { mutableStateOf("選擇正版動畫來源後按 OK 載入。") }
    var mediaState by remember { mutableStateOf(NativeMediaState(0)) }
    var mediaCards by remember { mutableStateOf(emptyList<NativeMediaCard>()) }
    var mediaStatus by remember { mutableStateOf("正在載入…") }
    var watchHistory by remember { mutableStateOf(WatchHistoryState()) }
    var controlCenterVisible by remember { mutableStateOf(false) }
    val activeDispatcher = remember(dispatcher) { dispatcher ?: RemoteCommandDispatcher() }
    val focusRequester = remember { FocusRequester() }

    fun recordWatch(card: NativeMediaCard) {
        watchHistory = watchHistory.record(card)
        state = state.copy(historyCount = watchHistory.entries.size)
    }

    fun handle(command: RemoteCommand) {
        if (screen == ShellScreen.YouTube || screen == ShellScreen.Bilibili) {
            if ((command == RemoteCommand.Back || command == RemoteCommand.Home) && mediaState.phase == NativeMediaPhase.Browser) {
                screen = ShellScreen.Launcher
            } else {
                val next = mediaState.reduce(command)
                val action = next.pendingAction
                if (action?.startsWith("play:") == true) {
                    val index = action.substringAfter(':').toIntOrNull() ?: 0
                    mediaCards.getOrNull(index)?.let { card ->
                        mediaStatus = adapter.playMedia(card).fold(
                        { recordWatch(card); "正在播放 ${card.title}" },
                        { "播放失敗：${it.message}" },
                    )
                    }
                    mediaState = next.clearAction()
                } else {
                    mediaState = next
                }
            }
            return
        }
        if (screen == ShellScreen.Anime) {
            val next = animeState.reduce(command)
            val action = next.pendingAction
            when {
                action == "exit" -> {
                    animeState = next.clearAction()
                    if (animeOnly) adapter.exitApp() else screen = ShellScreen.Launcher
                }
                action?.startsWith("play:") == true -> {
                    val index = action.substringAfter(':').toIntOrNull() ?: 0
                    animeCards.getOrNull(index)?.let { card ->
                        animeStatus = adapter.playMedia(card).fold(
                            { recordWatch(card); "正在播放 ${card.title}" },
                            { "播放失敗：${it.message}" },
                        )
                    }
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
                    state = state.copy(status = adapter.playMedia(card).fold(
                        { "正在續播 ${card.title}" },
                        { "播放失敗：${it.message}" },
                    ))
                }
                LauncherFocus.Apps -> state.focusedApp?.let { app ->
                    if (app.id == "anime") {
                        screen = ShellScreen.Anime
                        return@let
                    }
                    if (app.id == "youtube") {
                        screen = ShellScreen.YouTube
                        return@let
                    }
                    if (app.id == "bilibili") {
                        screen = ShellScreen.Bilibili
                        return@let
                    }
                    val result = if (app.isSystemSettings) adapter.openSystemSettings() else adapter.launch(app)
                    state = state.copy(status = result.fold({ "正在開啟 ${app.name}" }, { "無法開啟 ${app.name}：${it.message}" }))
                }
            }
            RemoteCommand.Menu -> controlCenterVisible = !controlCenterVisible
            RemoteCommand.Home, RemoteCommand.Back -> controlCenterVisible = false
            else -> state = state.reduce(command)
        }
    }

    DisposableEffect(activeDispatcher) {
        val unsubscribe = activeDispatcher.subscribe(::handle)
        onDispose(unsubscribe)
    }
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
    LaunchedEffect(screen) {
        val service = when (screen) {
            ShellScreen.YouTube -> NativeMediaService.YouTube
            ShellScreen.Bilibili -> NativeMediaService.Bilibili
            else -> null
        } ?: return@LaunchedEffect
        mediaStatus = "正在載入${if (service == NativeMediaService.YouTube) " YouTube" else " Bilibili"}…"
        val result = withContext(Dispatchers.Default) { adapter.fetchMediaFeed(service) }
        result.fold(
            onSuccess = { cards ->
                mediaCards = cards
                mediaState = NativeMediaState(cards.size)
                mediaStatus = "已載入 ${cards.size} 部影片"
            },
            onFailure = {
                mediaCards = emptyList()
                mediaState = NativeMediaState(0)
                mediaStatus = "載入失敗：${it.message}"
            },
        )
    }
    LaunchedEffect(screen, animeState.phase, animeState.focusedSource) {
        if (screen != ShellScreen.Anime || animeState.phase != CrossPlatformAnimePhase.Loading) return@LaunchedEffect
        val service = if (animeState.focusedSource == 0) NativeMediaService.YouTube else NativeMediaService.Bilibili
        animeStatus = "正在載入${if (service == NativeMediaService.YouTube) "官方 YouTube 動畫" else "Bilibili 動畫"}…"
        withContext(Dispatchers.Default) { adapter.fetchMediaFeed(service) }.fold(
            onSuccess = { cards ->
                animeCards = cards
                animeState = animeState.loaded(cards.size)
                animeStatus = "已載入 ${cards.size} 部可播放內容，按 OK 播放。"
            },
            onFailure = {
                animeCards = emptyList()
                animeState = animeState.failed()
                animeStatus = "動畫來源載入失敗：${it.message}"
            },
        )
    }

    TVShellBackdrop {
        Box(
            Modifier.fillMaxSize()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                event.key.toRemoteCommand()?.let { handle(it); true } ?: false
            }
            .focusRequester(focusRequester)
            .focusable()
        ) {
        when (screen) {
            ShellScreen.Launcher -> Launcher(state, watchHistory.entries)
            ShellScreen.Anime -> AnimeBrowser(animeState, animeCards, animeStatus)
            ShellScreen.YouTube -> NativeMediaRoute("YouTube", listOf("推薦", "熱門", "訂閱", "搜尋"), mediaState, mediaCards, mediaStatus)
            ShellScreen.Bilibili -> NativeMediaRoute("Bilibili", listOf("推薦", "熱門", "排行榜", "動態"), mediaState, mediaCards, mediaStatus)
        }
        if (controlCenterVisible) ControlCenter(onSettings = { adapter.openSystemSettings() })
        }
    }
}

private enum class ShellScreen { Launcher, Anime, YouTube, Bilibili }

@Composable
private fun NativeMediaRoute(
    title: String,
    tabs: List<String>,
    state: NativeMediaState,
    cards: List<NativeMediaCard>,
    status: String,
) {
    if (state.phase == NativeMediaPhase.Player) {
        NativeMediaPlayer(title, cards.getOrNull(state.focusedCard), state, status)
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
    val listState = rememberLazyListState()
    LaunchedEffect(state.focusedCard) {
        if (!state.isTopNavigationFocused && cards.isNotEmpty()) listState.animateScrollToItem(state.focusedCard)
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text(title, color = Color.White, fontSize = 58.sp, fontWeight = FontWeight.Bold)
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
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(34.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            itemsIndexed(cards, key = { _, card -> card.id }) { index, card ->
                MediaTile(card, !state.isTopNavigationFocused && state.focusedCard == index)
            }
        }
        Text(status, color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
    }
}

@Composable
private fun NativeMediaPlayer(
    service: String,
    card: NativeMediaCard?,
    state: NativeMediaState,
    status: String,
) {
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
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Text(if (state.isPlaying) "▶" else "Ⅱ", color = Color.White, fontSize = 72.sp, fontWeight = FontWeight.Bold)
                Text(card?.title ?: "正在準備播放", color = Color.White, fontSize = 36.sp, fontWeight = FontWeight.Bold)
                Text(
                    if (state.pendingSeekSeconds == 0) status else "已跳轉 ${if (state.pendingSeekSeconds > 0) "+" else ""}${state.pendingSeekSeconds} 秒",
                    color = Color.White.copy(alpha = .66f),
                    fontSize = 22.sp,
                )
            }
        }
        Text("OK 暫停／播放 · 左右快轉或倒轉 15 秒 · Back 返回影片列表", color = Color.White.copy(alpha = .68f), fontSize = 22.sp)
    }
}

@Composable
private fun MediaTile(card: NativeMediaCard, focused: Boolean) {
    val scale by animateFloatAsState(if (focused) 1.06f else 1f, tween(TVShellDesign.FocusAnimationMilliseconds))
    val shape = RoundedCornerShape(16.dp)
    Column(Modifier.width(300.dp).scale(scale), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier.size(width = 300.dp, height = 169.dp)
                .tvShellSurface(TVSurfaceRole.Content, isFocused = focused, cornerRadius = 16f),
            contentAlignment = Alignment.Center,
        ) {
            Text("▶", color = if (focused) Color.Black else Color.White, fontSize = 40.sp, fontWeight = FontWeight.Bold)
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
        if (state.focus == LauncherFocus.Apps && state.apps.isNotEmpty()) listState.animateScrollToItem(state.focusedIndex)
    }
    LaunchedEffect(state.focusedHistoryIndex, state.focus) {
        if (state.focus == LauncherFocus.History && history.isNotEmpty()) historyListState.animateScrollToItem(state.focusedHistoryIndex)
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
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(42.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            itemsIndexed(state.apps, key = { _, app -> app.id }) { index, app ->
                AppTile(app, state.focus == LauncherFocus.Apps && index == state.focusedIndex)
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
                    MediaTile(card, state.focus == LauncherFocus.History && index == state.focusedHistoryIndex)
                }
            }
        }
        Spacer(Modifier.height(34.dp))
        Text("方向鍵移動，OK 開啟，長按 Menu 開啟快捷設定。", color = Color.White.copy(alpha = .62f), fontSize = 22.sp)
        Text(state.status, color = Color.White.copy(alpha = .48f), fontSize = 18.sp, modifier = Modifier.padding(top = 10.dp))
    }
}

@Composable
private fun AppTile(app: ShellApp, focused: Boolean) {
    val scale by animateFloatAsState(
        if (focused) 1.06f else 1f,
        tween(TVShellDesign.FocusAnimationMilliseconds),
    )
    Column(
        Modifier.width(222.dp).scale(scale)
            .offset { IntOffset(0, if (focused) -10 else 0) },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(width = 222.dp, height = 143.dp)
                .tvShellSurface(TVSurfaceRole.Dock, isFocused = focused, cornerRadius = 24f),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                app.name.take(2),
                color = if (focused) Color(0xFF17181B) else Color.White,
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        Spacer(Modifier.height(14.dp))
        Text(app.name, color = Color.White, fontSize = 25.sp, maxLines = 1)
    }
}

@Composable
private fun AnimeBrowser(state: CrossPlatformAnimeBrowserState, cards: List<NativeMediaCard>, status: String) {
    val sources = listOf("官方 YouTube 動畫", "Bilibili 動畫")
    val listState = rememberLazyListState()
    LaunchedEffect(state.focusedSource, state.focusedCard, state.phase) {
        val target = if (state.phase == CrossPlatformAnimePhase.Titles) state.focusedCard else state.focusedSource
        if (target >= 0) listState.animateScrollToItem(target)
    }
    Column(
        Modifier.fillMaxSize().padding(horizontal = 86.dp, vertical = 48.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Text("動畫", color = Color.White, fontSize = 58.sp, fontWeight = FontWeight.Bold)
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
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(42.dp),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (state.phase == CrossPlatformAnimePhase.Titles) {
                itemsIndexed(cards, key = { _, card -> card.id }) { index, card ->
                    MediaTile(card, index == state.focusedCard)
                }
            } else {
                itemsIndexed(sources, key = { _, title -> title }) { index, title ->
                    AppTile(ShellApp("anime-source:$title", title, "可播放正版內容"), !state.isTopNavigationFocused && index == state.focusedSource)
                }
            }
        }
        Text(
            status,
            color = Color.White.copy(alpha = .62f),
            fontSize = 22.sp,
        )
    }
}

@Composable
private fun ControlCenter(onSettings: () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = .38f)), contentAlignment = Alignment.CenterEnd) {
        Column(
            Modifier.width(480.dp).fillMaxSize()
                .tvShellSurface(TVSurfaceRole.Panel, cornerRadius = 0f)
                .padding(42.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text("控制中心", color = Color.White, fontSize = 38.sp, fontWeight = FontWeight.Bold)
            Text("音量 70%", color = Color.White, fontSize = 25.sp)
            Text("彈幕：開啟 · 100% · 速度 100%", color = Color.White.copy(alpha = .72f), fontSize = 21.sp)
            Text("按 OK 開啟系統設定", color = Color.White.copy(alpha = .58f), fontSize = 19.sp)
        }
    }
}

private fun Key.toRemoteCommand(): RemoteCommand? = when (this) {
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
