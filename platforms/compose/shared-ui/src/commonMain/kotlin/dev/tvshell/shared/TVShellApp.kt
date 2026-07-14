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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
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
    var controlCenterState by remember { mutableStateOf(ControlCenterState()) }
    var settingsState by remember { mutableStateOf(SettingsState()) }
    val activeDispatcher = remember(dispatcher) { dispatcher ?: RemoteCommandDispatcher() }
    val focusRequester = remember { FocusRequester() }

    fun recordWatch(card: NativeMediaCard) {
        watchHistory = watchHistory.record(card)
        state = state.copy(historyCount = watchHistory.entries.size)
    }

    fun handle(command: RemoteCommand) {
        if (controlCenterVisible) {
            val next = controlCenterState.reduce(command)
            when (next.pendingAction) {
                "close" -> controlCenterVisible = false
                "home" -> {
                    controlCenterVisible = false
                    screen = if (animeOnly) ShellScreen.Anime else ShellScreen.Launcher
                }
                "settings" -> {
                    controlCenterVisible = false
                    settingsState = SettingsState(preferences = controlCenterState)
                    screen = ShellScreen.Settings
                }
            }
            controlCenterState = next.clearAction()
            return
        }
        if (command == RemoteCommand.Menu) {
            controlCenterVisible = true
            return
        }
        if (screen == ShellScreen.Settings) {
            val next = settingsState.reduce(command)
            when (next.pendingAction) {
                "exit" -> screen = if (animeOnly) ShellScreen.Anime else ShellScreen.Launcher
                "video-source" -> adapter.openSystemSettings()
                "credentials" -> adapter.openSystemSettings()
            }
            controlCenterState = next.preferences
            settingsState = next.clearAction()
            return
        }
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
            ShellScreen.Settings -> SettingsScreen(settingsState)
        }
        if (controlCenterVisible) ControlCenter(controlCenterState)
        }
    }
}

private enum class ShellScreen { Launcher, Anime, YouTube, Bilibili, Settings }

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
    val listState = rememberLazyGridState()
    LaunchedEffect(state.focusedCard) {
        if (!state.isTopNavigationFocused && cards.isNotEmpty()) listState.animateScrollToItem(state.focusedCard)
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
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalArrangement = Arrangement.spacedBy(32.dp),
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
    val thumbnail = NetworkThumbnailRequest(card.thumbnailURL)
    Column(Modifier.width(390.dp).scale(scale), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            Modifier.size(width = 390.dp, height = 219.dp)
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
            Box(
                Modifier.size(width = 166.dp, height = 102.dp)
                    .clip(RoundedCornerShape(TVShellVisual.AppIconCornerRadius.dp))
                    .background(appAccent(app)),
                contentAlignment = Alignment.Center,
            ) {
                Text(appGlyph(app), color = Color.White, fontSize = 42.sp, fontWeight = FontWeight.Bold)
            }
        }
        Spacer(Modifier.height(14.dp))
        Text(app.name, color = Color.White, fontSize = 25.sp, maxLines = 1)
    }
}

private fun appGlyph(app: ShellApp): String = when (app.id) {
    "youtube" -> "▶"
    "bilibili" -> "b"
    "anime" -> "動"
    else -> app.name.take(2)
}

private fun appAccent(app: ShellApp): Color = when (app.id) {
    "youtube" -> Color(0xFFD92128)
    "bilibili" -> Color(0xFFEE5486)
    "anime" -> Color(0xFF6A43B8)
    else -> Color(0xFF3A3E48)
}

@Composable
private fun SettingsScreen(state: SettingsState) {
    val listState = rememberLazyListState()
    LaunchedEffect(state.focusedItem) {
        listState.animateScrollToItem(state.focusedItem.ordinal)
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
    SettingsItem.Credentials -> state.credentialsSummary
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
private fun AnimeBrowser(state: CrossPlatformAnimeBrowserState, cards: List<NativeMediaCard>, status: String) {
    val sources = listOf("官方 YouTube 動畫", "Bilibili 動畫")
    val sourceListState = rememberLazyListState()
    val titleGridState = rememberLazyGridState()
    LaunchedEffect(state.focusedSource, state.focusedCard, state.phase) {
        if (state.phase == CrossPlatformAnimePhase.Titles && cards.isNotEmpty()) {
            titleGridState.animateScrollToItem(state.focusedCard)
        } else if (sources.isNotEmpty()) {
            sourceListState.animateScrollToItem(state.focusedSource)
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
        if (state.phase == CrossPlatformAnimePhase.Titles) {
            LazyVerticalGrid(
                columns = GridCells.Fixed(state.gridColumns),
                state = titleGridState,
                horizontalArrangement = Arrangement.spacedBy(28.dp),
                verticalArrangement = Arrangement.spacedBy(32.dp),
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                gridItemsIndexed(cards, key = { _, card -> card.id }) { index, card ->
                    MediaTile(card, !state.isTopNavigationFocused && index == state.focusedCard)
                }
            }
        } else {
            LazyRow(
                state = sourceListState,
                horizontalArrangement = Arrangement.spacedBy(42.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().weight(1f),
            ) {
                itemsIndexed(sources, key = { _, title -> title }) { index, title ->
                    AppTile(ShellApp("anime-source:$title", title, "可播放正版內容"), !state.isTopNavigationFocused && index == state.focusedSource)
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
private fun ControlCenter(state: ControlCenterState) {
    val gridState = rememberLazyGridState()
    LaunchedEffect(state.focusedItem) {
        gridState.animateScrollToItem(state.focusedItem.ordinal)
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
