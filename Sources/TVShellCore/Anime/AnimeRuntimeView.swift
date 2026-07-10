import AppKit
@preconcurrency import AVFoundation
import AVKit
import SwiftUI

public struct AnimeRuntimeView: View {
    public let app: TVAppProfile
    @EnvironmentObject private var appState: AppState
    @StateObject private var controller = AnimeRuntimeController()

    public init(app: TVAppProfile) {
        self.app = app
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ZStack {
                TVControlBackdrop()

                switch controller.state.phase {
                case .titles:
                    titleBrowser(metrics: metrics)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .details:
                    detailBrowser(metrics: metrics)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .episodes:
                    episodeBrowser(metrics: metrics, size: proxy.size)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .playing:
                    player(metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }

                if controller.isKeyboardVisible {
                    VirtualKeyboardView(
                        title: "搜尋動漫",
                        state: controller.keyboardState,
                        metrics: metrics
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(20)
                }

                if controller.isStreamPickerVisible {
                    AnimeStreamPickerView(
                        episodeTitle: controller.pendingStreamEpisodeTitle,
                        choices: controller.streamChoices,
                        focusedIndex: controller.focusedStreamChoiceIndex,
                        metrics: metrics
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(22)
                }

                if controller.isDownloadManagerVisible {
                    torrentDownloadManager(metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                        .zIndex(18)
                }
            }
            .animation(TVMotion.runtime, value: controller.state.phase)
            .foregroundStyle(.white)
            .onAppear {
                controller.updateTitleColumns(titleGridColumns(for: metrics, size: proxy.size))
                controller.updateEpisodeColumns(episodeGridColumns(for: metrics, size: proxy.size))
            }
            .onChange(of: proxy.size) { _, newSize in
                controller.updateTitleColumns(titleGridColumns(for: TVMetrics(size: newSize), size: newSize))
                controller.updateEpisodeColumns(episodeGridColumns(for: TVMetrics(size: newSize), size: newSize))
            }
        }
        .task {
            controller.updateWatchHistory(appState.watchingHistory)
            controller.updatePreferredStreams(appState.preferredAnimeStreams)
            await controller.load(
                sourceProvider: AnimeSourceProviderFactory.provider(
                    catalog: appState.animeSourceCatalog,
                    youtubeCredentials: appState.youtubeCredentials
                ),
                danmakuProvider: DandanplayDanmakuProvider(credentials: appState.dandanplayCredentials)
            )
            if let entry = appState.consumePendingWatchHistory(kind: .anime) {
                await controller.resume(from: entry)
            }
        }
        .onChange(of: appState.watchingHistory) { _, history in
            controller.updateWatchHistory(history)
        }
        .onChange(of: appState.preferredAnimeStreams) { _, preferences in
            controller.updatePreferredStreams(preferences)
        }
        .onChange(of: appState.youtubeCredentials) { _, _ in
            reloadConfiguredSources()
        }
        .onChange(of: appState.dandanplayCredentials) { _, _ in
            reloadConfiguredSources()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.state.phase) { _, phase in
            setStatusClockHidden(phase == .playing)
        }
    }

    private func reloadConfiguredSources() {
        Task {
            await controller.load(
                sourceProvider: AnimeSourceProviderFactory.provider(
                    catalog: appState.animeSourceCatalog,
                    youtubeCredentials: appState.youtubeCredentials
                ),
                danmakuProvider: DandanplayDanmakuProvider(credentials: appState.dandanplayCredentials)
            )
        }
    }

    private func detailBrowser(metrics: TVMetrics) -> some View {
        let title = controller.focusedTitle

        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 48 * metrics.scale) {
                AnimeTitleCard(
                    title: title ?? AnimeSearchResult(id: "empty", title: "動漫", subtitle: nil, coverURL: nil, episodes: []),
                    isFocused: false,
                    metrics: metrics
                )
                .scaleEffect(1.08)

                VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                    animeHeader(
                        metrics: metrics,
                        title: title?.title ?? "動漫詳情",
                        subtitle: title?.subtitle ?? controller.statusText
                    )

                    if let detail = title?.detailLine {
                        Text(detail)
                            .font(.system(size: 26 * metrics.scale, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(3)
                    }

                    Text(title?.summaryText ?? "選擇開始觀看後進入選集。")
                        .font(.system(size: 27 * metrics.scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(8)

                    Text("開始觀看")
                        .font(.system(size: 34 * metrics.scale, weight: .bold))
                        .padding(.horizontal, 34 * metrics.scale)
                        .padding(.vertical, 22 * metrics.scale)
                        .liquidGlassCard(isFocused: true, cornerRadius: 26 * metrics.scale)

                    Text("OK 開始觀看，Back 回封面牆，Menu 搜尋動漫。")
                        .font(.system(size: 24 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .padding(.bottom, 54 * metrics.scale)
        }
        .scrollIndicators(.hidden)
    }

    private func episodeGridColumns(for metrics: TVMetrics, size: CGSize) -> Int {
        Self.adaptiveColumns(
            availableWidth: size.width - (metrics.horizontalPadding * 2),
            minimumWidth: 230 * metrics.scale,
            spacing: 22 * metrics.scale
        )
    }

    private func fixedEpisodeCardWidth(for metrics: TVMetrics, size: CGSize) -> Double {
        let count = episodeGridColumns(for: metrics, size: size)
        let spacing = 22 * metrics.scale
        let availableWidth = max(230 * metrics.scale, size.width - (metrics.horizontalPadding * 2))
        return (availableWidth - (Double(count - 1) * spacing)) / Double(count)
    }

    private func titleGridColumns(for metrics: TVMetrics, size: CGSize) -> Int {
        Self.adaptiveColumns(
            availableWidth: size.width - (metrics.horizontalPadding * 2),
            minimumWidth: 184 * metrics.scale,
            spacing: 18 * metrics.scale
        )
    }

    private static func adaptiveColumns(availableWidth: Double, minimumWidth: Double, spacing: Double) -> Int {
        max(1, Int((max(availableWidth, minimumWidth) + spacing) / (minimumWidth + spacing)))
    }

    private func titleBrowser(metrics: TVMetrics) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                    animeHeader(metrics: metrics, title: app.name, subtitle: controller.statusText)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 184 * metrics.scale), spacing: 18 * metrics.scale)],
                        alignment: .leading,
                        spacing: 18 * metrics.scale
                    ) {
                        ForEach(Array(controller.titles.enumerated()), id: \.element.id) { index, title in
                            AnimeTitleCard(
                                title: title,
                                isFocused: index == controller.state.focusedTitleIndex,
                                metrics: metrics
                            )
                            .id("anime-title-\(index)")
                        }
                    }

                    Text("方向鍵選作品，OK 進入詳情，Menu 搜尋動漫，Home 回主畫面。")
                        .font(.system(size: 25 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 54 * metrics.scale)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.state.focusedTitleIndex) { _, index in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("anime-title-\(index)", anchor: .center)
                }
            }
            .onChange(of: controller.titles.count) { _, _ in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("anime-title-\(controller.state.focusedTitleIndex)", anchor: .center)
                }
            }
        }
    }

    private func episodeBrowser(metrics: TVMetrics, size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                let columns = episodeGridColumns(for: metrics, size: size)
                let cardWidth = fixedEpisodeCardWidth(for: metrics, size: size)
                let rows = AnimeEpisodeGridLayout.rows(itemCount: controller.episodes.count, columns: columns)

                VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                    animeHeader(
                        metrics: metrics,
                        title: controller.currentTitle?.title ?? "選集",
                        subtitle: controller.currentTitle?.subtitle ?? controller.statusText
                    )

                    LazyVStack(alignment: .leading, spacing: 22 * metrics.scale) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 22 * metrics.scale) {
                                ForEach(row, id: \.self) { offset in
                                    if controller.episodes.indices.contains(offset) {
                                        EpisodeCard(
                                            episode: controller.episodes[offset],
                                            isFocused: offset == controller.state.focusedEpisodeIndex,
                                            metrics: metrics
                                        )
                                        .frame(width: cardWidth)
                                        .id("anime-episode-\(offset)")
                                    }
                                }
                            }
                        }
                    }

                    Text("方向鍵選集，OK 播放，Back 回詳情，Menu 開啟下載管理。")
                        .font(.system(size: 25 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 54 * metrics.scale)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.state.focusedEpisodeIndex) { _, index in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("anime-episode-\(index)", anchor: .center)
                }
            }
            .onChange(of: controller.episodes.count) { _, _ in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("anime-episode-\(controller.state.focusedEpisodeIndex)", anchor: .center)
                }
            }
        }
    }

    private func torrentDownloadManager(metrics: TVMetrics) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                    Text("BT 下載管理")
                        .font(.system(size: 58 * metrics.scale, weight: .bold))
                    Text("上下選擇，OK 或 Menu 刪除，Back 關閉。")
                        .font(.system(size: 25 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                if controller.torrentDownloads.isEmpty {
                    Text("目前沒有已下載或下載中的 BT 快取。")
                        .font(.system(size: 30 * metrics.scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 220 * metrics.scale, alignment: .center)
                        .liquidGlassCard(isFocused: false, cornerRadius: 28 * metrics.scale)
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 14 * metrics.scale) {
                                ForEach(Array(controller.torrentDownloads.enumerated()), id: \.element.id) { index, item in
                                    TorrentDownloadRow(
                                        item: item,
                                        isFocused: index == controller.focusedTorrentDownloadIndex,
                                        metrics: metrics
                                    )
                                    .id("torrent-download-\(index)")
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: controller.focusedTorrentDownloadIndex) { _, index in
                            withAnimation(TVMotion.focus) {
                                scrollProxy.scrollTo("torrent-download-\(index)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .padding(42 * metrics.scale)
            .frame(maxWidth: min(980 * metrics.scale, 980), maxHeight: min(760 * metrics.scale, 760), alignment: .topLeading)
            .liquidGlassCard(isFocused: true, cornerRadius: 32 * metrics.scale)
            .padding(.horizontal, metrics.horizontalPadding)
        }
    }

    private func animeHeader(metrics: TVMetrics, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            Text(title)
                .font(.system(size: 76 * metrics.scale, weight: .bold))
                .lineLimit(2)
            Text(subtitle)
                .font(.system(size: 28 * metrics.scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
    }

    private func player(metrics: TVMetrics) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let youtubeVideoID = controller.currentYouTubeVideoID {
                YouTubePlayerView(
                    videoID: youtubeVideoID,
                    startSeconds: controller.currentYouTubeResumeTime,
                    restartOnSelect: controller.canRestartFromBeginningWithSelect,
                    onPlaybackTime: { time, isPlaying in
                        controller.updateYouTubeDanmaku(time: time, isPlaying: isPlaying)
                    }
                )
                    .ignoresSafeArea()
            } else if let vlcURL = controller.currentVLCURL {
                InternalVLCPlayerSurface(
                    url: vlcURL,
                    headers: controller.currentVLCHeaders,
                    onStatus: { status in
                        controller.updateInternalVLCStatus(status)
                    }
                )
                    .ignoresSafeArea()
            } else {
                AnimePlayerSurface(player: controller.player)
                    .ignoresSafeArea()
            }

            if controller.state.isDanmakuVisible {
                DanmakuOverlay(
                    comments: controller.visibleDanmaku,
                    currentTime: controller.danmakuPlaybackTime,
                    sampleDate: controller.danmakuPlaybackDate,
                    isClockRunning: controller.isDanmakuClockRunning,
                    settings: appState.danmakuDisplaySettings,
                    metrics: metrics
                )
                    .transition(.opacity)
                    .zIndex(3)
            }

            if controller.isPlayerHUDVisible {
                VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                    Text(controller.playingTitle)
                        .font(.system(size: 38 * metrics.scale, weight: .bold))
                    Text("播放/暫停控制播放，HUD 顯示時 OK 從 0:00 重播，HUD 消失後 OK 播放暫停。")
                        .font(.system(size: 22 * metrics.scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(28 * metrics.scale)
                .liquidGlassCard(isFocused: true, cornerRadius: 22 * metrics.scale)
                .padding(50 * metrics.scale)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 12 * metrics.scale) {
                Text(controller.state.isDanmakuVisible ? "彈幕 ON" : "彈幕 OFF")
                Text(controller.danmakuStatusText)
                Text(controller.subtitleStatusText)
            }
            .font(.system(size: 22 * metrics.scale, weight: .bold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 20 * metrics.scale)
            .padding(.vertical, 12 * metrics.scale)
            .liquidGlassCard(isFocused: false, cornerRadius: 18 * metrics.scale)
            .padding(.top, 50 * metrics.scale)
            .padding(.trailing, 50 * metrics.scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .background(.black)
    }
}

private func setStatusClockHidden(_ hidden: Bool) {
    NotificationCenter.default.post(
        name: .tvShellSetStatusClockHidden,
        object: nil,
        userInfo: [StatusClockNotification.hiddenKey: hidden]
    )
}

@MainActor
final class AnimeRuntimeController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var state = AnimeRuntimeState(episodeCount: 0)
    @Published private(set) var titles: [AnimeSearchResult] = []
    @Published private(set) var currentTitle: AnimeSearchResult?
    @Published private(set) var episodes: [AnimeEpisode] = []
    @Published private(set) var statusText = "正在載入動畫源..."
    @Published private(set) var visibleDanmaku: [DanmakuComment] = []
    @Published private(set) var currentYouTubeVideoID: String?
    @Published private(set) var currentVLCURL: URL?
    @Published private(set) var currentVLCHeaders: [String: String] = [:]
    @Published private(set) var currentYouTubeResumeTime: Double = 0
    @Published private(set) var danmakuStatusText = "彈幕未載入"
    @Published private(set) var subtitleStatusText = "字幕：中文字幕優先"
    @Published private(set) var danmakuPlaybackTime: Double = 0
    @Published private(set) var danmakuPlaybackDate = Date()
    @Published private(set) var isDanmakuClockRunning = false
    @Published private(set) var isPlayerHUDVisible = false
    @Published private(set) var canRestartFromBeginningWithSelect = false
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var isStreamPickerVisible = false
    @Published private(set) var streamChoices: [AnimeStreamCandidate] = []
    @Published private(set) var focusedStreamChoiceIndex = 0
    @Published private(set) var isDownloadManagerVisible = false
    @Published private(set) var torrentDownloads: [TorrentCachedDownload] = []
    @Published private(set) var focusedTorrentDownloadIndex = 0
    @Published private(set) var keyboardState = VirtualKeyboardState(text: "", layout: .zhuyin)

    private var sourceProvider: (any AnimeSourceProvider)?
    private var danmakuProvider: any DanmakuProvider
    private var comments: [DanmakuComment] = []
    private var titleColumns = 6
    private var episodeColumns = 4
    private var currentQuery = ""
    private var watchHistory: [WatchHistoryEntry] = []
    private var preferredStreams: [String: String] = [:]
    private var pendingStreamEpisode: AnimeEpisode?
    private var currentPlayingEpisode: AnimeEpisode?
    private var lastRecordedMediaID: String?
    private var lastRecordedTime: Double = -1
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private nonisolated(unsafe) var timeObserver: Any?
    private nonisolated(unsafe) var itemEndObserver: NSObjectProtocol?
    private nonisolated(unsafe) var itemObserver: NSKeyValueObservation?
    private var hidePlayerHUDTask: Task<Void, Never>?
    private var mediaState = MediaControlState()
    private let torrentPlaybackEngine = Aria2TorrentPlaybackEngine()

    init(
        sourceProvider: (any AnimeSourceProvider)? = nil,
        danmakuProvider: any DanmakuProvider = AnimeDemoCatalog.danmakuProvider()
    ) {
        self.sourceProvider = sourceProvider
        self.danmakuProvider = danmakuProvider
        observer = NotificationCenter.default.addObserver(
            forName: .tvShellRuntimeCommand,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handle(command)
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        itemObserver?.invalidate()
        hidePlayerHUDTask?.cancel()
    }

    var playingTitle: String {
        guard episodes.indices.contains(state.focusedEpisodeIndex) else {
            return currentTitle?.title ?? "動畫"
        }
        return "\(currentTitle?.title ?? "動畫") · \(episodes[state.focusedEpisodeIndex].title)"
    }

    var focusedTitle: AnimeSearchResult? {
        guard titles.indices.contains(state.focusedTitleIndex) else {
            return nil
        }
        return titles[state.focusedTitleIndex]
    }

    var pendingStreamEpisodeTitle: String {
        pendingStreamEpisode?.title ?? "選擇播放來源"
    }

    func load(
        sourceProvider provider: (any AnimeSourceProvider)? = nil,
        danmakuProvider: (any DanmakuProvider)? = nil
    ) async {
        if let provider {
            sourceProvider = provider
        }
        if let danmakuProvider {
            self.danmakuProvider = danmakuProvider
        }

        guard let sourceProvider else {
            statusText = "沒有可用動畫來源。請先到動漫來源頁啟用來源。"
            return
        }

        do {
            let keyword = currentQuery
            titles = try await sourceProvider.search(AnimeSearchQuery(keyword: keyword))
            guard titles.isEmpty == false else {
                statusText = "沒有找到動畫。"
                return
            }

            state = AnimeRuntimeState(titleCount: titles.count, episodeCount: 0)
            if keyword.isEmpty {
                statusText = "來源：\(sourceProvider.displayName) · 首頁推薦 \(titles.count) 部作品"
            } else {
                statusText = "來源：\(sourceProvider.displayName) · 找到 \(titles.count) 部作品 · 搜尋：\(keyword)"
            }
        } catch {
            statusText = "動畫源載入失敗：\(error.localizedDescription)"
        }
    }

    func stop() {
        recordPlaybackProgress(force: true)
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentYouTubeVideoID = nil
        currentVLCURL = nil
        currentVLCHeaders = [:]
        currentYouTubeResumeTime = 0
        isDanmakuClockRunning = false
        hidePlayerHUDTask?.cancel()
        isPlayerHUDVisible = false
        canRestartFromBeginningWithSelect = false
        setStatusClockHidden(false)
    }

    func updateWatchHistory(_ history: [WatchHistoryEntry]) {
        watchHistory = history
    }

    func updatePreferredStreams(_ preferences: [String: String]) {
        preferredStreams = preferences
    }

    func updateEpisodeColumns(_ columns: Int) {
        episodeColumns = max(1, columns)
    }

    func updateTitleColumns(_ columns: Int) {
        titleColumns = max(1, columns)
    }

    private func handle(_ command: RemoteCommand) {
        if isKeyboardVisible {
            handleKeyboard(command)
            return
        }

        if isStreamPickerVisible {
            handleStreamPicker(command)
            return
        }

        if isDownloadManagerVisible {
            handleDownloadManager(command)
            return
        }

        if state.phase == .titles || state.phase == .details, command == .menu {
            keyboardState = VirtualKeyboardState(text: currentQuery, layout: .zhuyin)
            isKeyboardVisible = true
            statusText = "動漫搜尋"
            return
        }

        let previousPhase = state.phase
        state.apply(command, titleColumns: titleColumns, episodeColumns: episodeColumns)

        if previousPhase == .titles, state.phase == .titles {
            currentTitle = focusedTitle
        }

        if previousPhase == .titles, command == .back {
            NotificationCenter.default.post(name: .tvShellRequestLauncher, object: nil)
            return
        }

        if previousPhase == .titles, state.phase == .details {
            currentTitle = focusedTitle
            return
        }

        if previousPhase == .details, state.phase == .episodes {
            Task { await loadFocusedTitleEpisodes() }
            return
        }

        if previousPhase == .episodes, state.phase == .playing {
            Task { await playFocusedEpisode() }
            if episodes.indices.contains(state.focusedEpisodeIndex) {
                let episode = episodes[state.focusedEpisodeIndex]
                let mediaID = watchMediaID(for: episode)
                NotificationCenter.default.post(
                    name: .tvShellRecordWatch,
                    object: nil,
                    userInfo: [
                        WatchHistoryNotification.entryKey: WatchHistoryEntry(
                            title: currentTitle?.title ?? episode.title,
                            subtitle: episode.title,
                            kind: .anime,
                            mediaID: mediaID,
                            resumeTimeSeconds: resumeTime(for: mediaID)
                        )
                    ]
                )
            }
            return
        }

        if previousPhase == .episodes, state.phase == .episodes, command == .menu {
            openDownloadManager()
            return
        }

        if previousPhase == .playing, state.phase == .episodes {
            stop()
            statusText = "已回到選集。"
            return
        }

        if state.phase == .playing {
            handlePlayback(command)
        }
    }

    private func handleKeyboard(_ command: RemoteCommand) {
        let action = keyboardState.apply(command)
        switch action {
        case .none, .textChanged:
            break
        case let .submitted(query):
            isKeyboardVisible = false
            currentQuery = query
            titles = []
            episodes = []
            currentTitle = nil
            state = AnimeRuntimeState(titleCount: 0, episodeCount: 0)
            statusText = "正在搜尋：\(query)..."
            Task { await load() }
        case .cancelled:
            isKeyboardVisible = false
            statusText = "已關閉搜尋"
        }
    }

    private func openDownloadManager() {
        refreshTorrentDownloads()
        isDownloadManagerVisible = true
        statusText = torrentDownloads.isEmpty ? "目前沒有 BT 快取。" : "BT 下載管理"
    }

    private func handleDownloadManager(_ command: RemoteCommand) {
        switch command {
        case .up:
            focusedTorrentDownloadIndex = max(0, focusedTorrentDownloadIndex - 1)
        case .down:
            focusedTorrentDownloadIndex = min(max(torrentDownloads.count - 1, 0), focusedTorrentDownloadIndex + 1)
        case .select, .menu:
            deleteFocusedTorrentDownload()
        case .back, .home:
            isDownloadManagerVisible = false
            refreshTorrentDownloads()
        default:
            break
        }
    }

    private func refreshTorrentDownloads() {
        torrentDownloads = torrentPlaybackEngine.cachedDownloads()
        focusedTorrentDownloadIndex = min(focusedTorrentDownloadIndex, max(torrentDownloads.count - 1, 0))
    }

    private func loadFocusedTitleEpisodes() async {
        guard titles.indices.contains(state.focusedTitleIndex),
              let sourceProvider
        else {
            statusText = "沒有可用作品。"
            return
        }

        let title = titles[state.focusedTitleIndex]
        do {
            currentTitle = title
            episodes = try await sourceProvider.episodes(for: title)
            state.openEpisodes(episodeCount: episodes.count)
            statusText = "\(title.title) · 已載入 \(episodes.count) 集"
        } catch {
            statusText = "選集載入失敗：\(error.localizedDescription)"
            state = AnimeRuntimeState(
                titleCount: titles.count,
                episodeCount: 0,
                focusedTitleIndex: state.focusedTitleIndex,
                phase: .details,
                isDanmakuVisible: state.isDanmakuVisible
            )
        }
    }

    private func playFocusedEpisode() async {
        guard episodes.indices.contains(state.focusedEpisodeIndex) else {
            statusText = "沒有可播放的集數。"
            return
        }

        let episode = episodes[state.focusedEpisodeIndex]
        guard let sourceProvider else {
            statusText = "沒有可用動畫來源。"
            state = AnimeRuntimeState(
                episodeCount: episodes.count,
                focusedEpisodeIndex: state.focusedEpisodeIndex,
                phase: .episodes,
                isDanmakuVisible: state.isDanmakuVisible
            )
            return
        }

        do {
            statusText = "正在解析 \(episode.title)..."
            let candidates = try await sourceProvider.streams(for: episode)
            guard candidates.isEmpty == false else {
                statusText = "沒有可用播放源。"
                state = AnimeRuntimeState(
                    episodeCount: episodes.count,
                    focusedEpisodeIndex: state.focusedEpisodeIndex,
                    phase: .episodes,
                    isDanmakuVisible: state.isDanmakuVisible
                )
                return
            }

            let mediaID = watchMediaID(for: episode)
            if let preferredURL = preferredStreams[mediaID],
               let preferredStream = candidates.first(where: { $0.url.absoluteString == preferredURL }) {
                await startPlayback(preferredStream, episode: episode)
                return
            }

            let needsExplicitConfirmation = candidates.contains { $0.headers["match"] == "fallback" }
            if candidates.count == 1, let stream = candidates.first, needsExplicitConfirmation == false {
                await startPlayback(stream, episode: episode)
                return
            }

            presentStreamPicker(candidates, episode: episode)
        } catch {
            if error as? YouTubeAPIError == .missingAPIKey {
                statusText = "需要設定 TVSHELL_YOUTUBE_API_KEY 才能搜尋並播放 YouTube 動漫來源。"
            } else {
                statusText = "解析失敗：\(error.localizedDescription)"
            }
            state = AnimeRuntimeState(
                episodeCount: episodes.count,
                focusedEpisodeIndex: state.focusedEpisodeIndex,
                phase: .episodes,
                isDanmakuVisible: state.isDanmakuVisible
            )
        }
    }

    private func presentStreamPicker(_ candidates: [AnimeStreamCandidate], episode: AnimeEpisode) {
        streamChoices = candidates.sorted { left, right in
            (left.priority, left.quality) > (right.priority, right.quality)
        }
        pendingStreamEpisode = episode
        focusedStreamChoiceIndex = 0
        isStreamPickerVisible = true
        statusText = "找到 \(streamChoices.count) 個播放結果，請選擇正確影片；選過後會自動記住。"
    }

    private func handleStreamPicker(_ command: RemoteCommand) {
        switch command {
        case .up, .left:
            focusedStreamChoiceIndex = max(0, focusedStreamChoiceIndex - 1)
        case .down, .right:
            focusedStreamChoiceIndex = min(max(streamChoices.count - 1, 0), focusedStreamChoiceIndex + 1)
        case .select:
            guard streamChoices.indices.contains(focusedStreamChoiceIndex),
                  let episode = pendingStreamEpisode
            else {
                return
            }
            let stream = streamChoices[focusedStreamChoiceIndex]
            NotificationCenter.default.post(
                name: .tvShellRememberAnimeStream,
                object: nil,
                userInfo: [
                    AnimeStreamPreferenceNotification.mediaIDKey: watchMediaID(for: episode),
                    AnimeStreamPreferenceNotification.streamURLKey: stream.url.absoluteString
                ]
            )
            dismissStreamPicker()
            Task { await startPlayback(stream, episode: episode) }
        case .back, .menu, .home:
            dismissStreamPicker()
            state = AnimeRuntimeState(
                titleCount: titles.count,
                episodeCount: episodes.count,
                focusedTitleIndex: state.focusedTitleIndex,
                focusedEpisodeIndex: state.focusedEpisodeIndex,
                phase: .episodes,
                isDanmakuVisible: state.isDanmakuVisible
            )
            statusText = "已取消選擇播放來源。"
        default:
            break
        }
    }

    private func dismissStreamPicker() {
        isStreamPickerVisible = false
        streamChoices = []
        pendingStreamEpisode = nil
        focusedStreamChoiceIndex = 0
    }

    private func startPlayback(_ stream: AnimeStreamCandidate, episode: AnimeEpisode) async {
        loadPlayer(stream, episode: episode)
        await loadDanmaku(for: episode, stream: stream)
    }

    func resume(from entry: WatchHistoryEntry) async {
        guard entry.kind == .anime,
              let mediaID = entry.mediaID,
              let episodeNumber = Int(mediaID.split(separator: ":").last ?? "")
        else {
            return
        }

        currentQuery = entry.title
        await load()
        guard let titleIndex = titles.firstIndex(where: { title in
            title.title.localizedCaseInsensitiveContains(entry.title)
                || entry.title.localizedCaseInsensitiveContains(title.title)
        }) ?? titles.indices.first
        else {
            statusText = "找不到觀看紀錄對應的作品：\(entry.title)"
            return
        }

        currentTitle = titles[titleIndex]
        do {
            episodes = try await sourceProvider?.episodes(for: titles[titleIndex]) ?? []
            let episodeIndex = episodes.firstIndex { $0.number == episodeNumber } ?? 0
            state = AnimeRuntimeState(
                titleCount: titles.count,
                episodeCount: episodes.count,
                focusedTitleIndex: titleIndex,
                focusedEpisodeIndex: episodeIndex,
                phase: .playing,
                isDanmakuVisible: state.isDanmakuVisible
            )
            await playFocusedEpisode()
        } catch {
            statusText = "無法恢復觀看紀錄：\(error.localizedDescription)"
        }
    }

    private func loadDanmaku(for episode: AnimeEpisode, stream: AnimeStreamCandidate) async {
        do {
            comments = DanmakuAggregator.merge([try await danmakuProvider.comments(for: episode.identity)])
            visibleDanmaku = Array(comments.prefix(5))
            danmakuStatusText = "\(comments.count) 條"
            statusText = "播放源：\(stream.quality) · Dandanplay 彈幕 \(comments.count) 條"
        } catch AnimeHTTPError.missingCredentials {
            comments = []
            visibleDanmaku = []
            danmakuStatusText = "未配置 Dandanplay"
            statusText = "播放源：\(stream.quality) · 尚未配置 Dandanplay AppID/AppSecret"
        } catch {
            comments = []
            visibleDanmaku = []
            danmakuStatusText = "載入失敗"
            statusText = "播放源：\(stream.quality) · 彈幕載入失敗：\(error.localizedDescription)"
        }
    }

    private func loadPlayer(_ stream: AnimeStreamCandidate, episode: AnimeEpisode) {
        showPlayerHUD(allowRestart: true)
        currentPlayingEpisode = episode
        lastRecordedMediaID = nil
        lastRecordedTime = -1
        if stream.url.scheme == "youtube" {
            currentYouTubeVideoID = stream.url.host ?? stream.url.absoluteString.replacingOccurrences(of: "youtube://", with: "")
            currentVLCURL = nil
            currentVLCHeaders = [:]
            currentYouTubeResumeTime = resumeTime(for: watchMediaID(for: episode))
            subtitleStatusText = "字幕：YouTube 中文字幕優先"
            if currentYouTubeResumeTime > 1 {
                statusText = "已從 \(WatchHistoryEntry.timeLabel(for: currentYouTubeResumeTime)) 繼續播放，HUD 顯示時按 OK 可回到 00:00。"
            }
            isDanmakuClockRunning = true
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        if stream.url.scheme == "magnet" || stream.headers["resolver"] == "torrent" {
            currentYouTubeVideoID = nil
            currentVLCURL = nil
            currentVLCHeaders = [:]
            currentYouTubeResumeTime = 0
            isDanmakuClockRunning = false
            player.pause()
            player.replaceCurrentItem(with: nil)
            subtitleStatusText = "字幕：BT 下載中"
            statusText = "正在啟動 BT 邊下邊播：\(stream.quality)..."
            Task { await playTorrent(stream, episode: episode) }
            return
        }

        currentYouTubeVideoID = nil
        currentVLCURL = nil
        currentVLCHeaders = [:]
        currentYouTubeResumeTime = 0
        playAVURL(stream.url, headers: playbackHeaders(from: stream.headers))
    }

    private func playTorrent(_ stream: AnimeStreamCandidate, episode: AnimeEpisode) async {
        do {
            try torrentPlaybackEngine.rememberDownload(
                for: stream,
                title: currentTitle?.title ?? episode.identity.subjectID,
                subtitle: episode.title
            )
            refreshTorrentDownloads()
            let fileURL = try await torrentPlaybackEngine.startStreaming(stream, episodeNumber: episode.number) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateTorrentProgress(progress)
                }
            }
            currentYouTubeVideoID = nil
            currentVLCURL = nil
            currentVLCHeaders = [:]
            subtitleStatusText = "字幕：正在尋找中文軌"
            statusText = "BT 已開始邊下邊播：\(fileURL.lastPathComponent)"
            playAVURL(fileURL)
            Task { await monitorTorrentProgress(stream, episode: episode) }
        } catch {
            subtitleStatusText = "字幕：BT 未就緒"
            statusText = error.localizedDescription
            state = AnimeRuntimeState(
                titleCount: titles.count,
                episodeCount: episodes.count,
                focusedTitleIndex: state.focusedTitleIndex,
                focusedEpisodeIndex: state.focusedEpisodeIndex,
                phase: .episodes,
                isDanmakuVisible: state.isDanmakuVisible
            )
        }
    }

    private func monitorTorrentProgress(_ stream: AnimeStreamCandidate, episode: AnimeEpisode) async {
        let directory = torrentPlaybackEngine.downloadDirectory(for: stream)
        for _ in 0..<900 where state.phase == .playing {
            updateTorrentProgress(torrentPlaybackEngine.downloadProgress(in: directory, episodeNumber: episode.number))
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func deleteFocusedTorrentDownload() {
        if isDownloadManagerVisible {
            guard torrentDownloads.indices.contains(focusedTorrentDownloadIndex) else {
                statusText = "目前沒有可刪除的 BT 下載。"
                return
            }
            let item = torrentDownloads[focusedTorrentDownloadIndex]
            do {
                try torrentPlaybackEngine.deleteDownload(id: item.id)
                refreshTorrentDownloads()
                statusText = "已刪除：\(item.title)"
            } catch {
                statusText = "刪除 BT 下載失敗：\(error.localizedDescription)"
            }
            return
        }

        guard episodes.indices.contains(state.focusedEpisodeIndex),
              let streamURL = episodes[state.focusedEpisodeIndex].identity.playbackURL
        else {
            statusText = "目前集數沒有可刪除的 BT 下載。"
            return
        }
        let stream = AnimeStreamCandidate(
            url: streamURL,
            quality: "BT / RSS",
            headers: ["resolver": "torrent"]
        )
        do {
            try torrentPlaybackEngine.deleteDownload(for: stream)
            refreshTorrentDownloads()
            statusText = "已刪除目前 BT 下載快取。"
        } catch {
            statusText = "刪除 BT 下載失敗：\(error.localizedDescription)"
        }
    }

    private func updateTorrentProgress(_ progress: TorrentDownloadProgress) {
        subtitleStatusText = "BT：已下載 \(progress.megabytesText)"
        statusText = "BT 下載中：\(progress.statusText)"
    }

    private func playbackHeaders(from headers: [String: String]) -> [String: String] {
        headers.filter { key, value in
            value.isEmpty == false && ["resolver", "source", "title", "episode", "match", "channel"].contains(key.lowercased()) == false
        }
    }

    private func playAVURL(_ url: URL, headers: [String: String] = [:]) {
        guard AnimePlaybackRenderer.renderer(for: url) == .avPlayer else {
            playInternalVLCURL(url, headers: headers)
            return
        }

        subtitleStatusText = "字幕：正在尋找中文軌"
        let resumeTime = currentPlayingEpisode
            .map(watchMediaID(for:))
            .map(resumeTime(for:)) ?? 0
        let asset = headers.isEmpty
            ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        itemObserver?.invalidate()
        itemObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if case .readyToPlay = item.status {
                    await self?.selectChineseSubtitleIfAvailable(for: item)
                    if resumeTime > 1 {
                        await self?.player.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 600))
                        self?.statusText = "已從 \(WatchHistoryEntry.timeLabel(for: resumeTime)) 繼續播放，HUD 顯示時按 OK 可回到 00:00。"
                    }
                    self?.player.play()
                } else if case .failed = item.status {
                    self?.statusText = item.error?.localizedDescription ?? "動畫播放失敗。"
                    self?.returnToEpisodesAfterPlaybackFailure("動畫播放失敗，可能是 BT 檔案尚未緩衝完成或檔案本身不可播放。")
                }
            }
        }

        player.replaceCurrentItem(with: item)
        mediaState = MediaControlState(isPlaying: true)
        isDanmakuClockRunning = true
        installTimeObserverIfNeeded()
        installShortPlaybackObserver(for: item)
    }

    private func installShortPlaybackObserver(for item: AVPlayerItem) {
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            Task { @MainActor in
                guard let self, item === self.player.currentItem else {
                    return
                }
                let played = self.player.currentTime().seconds
                if played < 5 {
                    self.returnToEpisodesAfterPlaybackFailure("播放很快結束：BT 檔案可能還沒緩衝完成，或此檔案不可播放。請稍等下載更多資料後再試。")
                }
            }
        }
    }

    private func returnToEpisodesAfterPlaybackFailure(_ message: String) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        mediaState = MediaControlState(isPlaying: false)
        isDanmakuClockRunning = false
        statusText = message
        subtitleStatusText = "字幕：播放未就緒"
        setStatusClockHidden(false)
        state = AnimeRuntimeState(
            titleCount: titles.count,
            episodeCount: episodes.count,
            focusedTitleIndex: state.focusedTitleIndex,
            focusedEpisodeIndex: state.focusedEpisodeIndex,
            phase: .episodes,
            isDanmakuVisible: state.isDanmakuVisible
        )
    }

    private func playInternalVLCURL(_ url: URL, headers: [String: String] = [:]) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentYouTubeVideoID = nil
        currentVLCURL = url
        currentVLCHeaders = headers
        isDanmakuClockRunning = true
        mediaState = MediaControlState(isPlaying: true)
        subtitleStatusText = "字幕：內建 VLC"
        statusText = "正在使用內建 VLC 播放：\(url.lastPathComponent)"
    }

    func updateInternalVLCStatus(_ status: String) {
        statusText = status
    }

    private func selectChineseSubtitleIfAvailable(for item: AVPlayerItem) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else {
            subtitleStatusText = "字幕：此來源沒有字幕軌"
            return
        }

        guard let option = group.options.first(where: isChineseSubtitleOption) else {
            subtitleStatusText = "字幕：沒有找到中文字幕"
            return
        }

        item.select(option, in: group)
        subtitleStatusText = "字幕：已選 \(option.displayName)"
    }

    private func isChineseSubtitleOption(_ option: AVMediaSelectionOption) -> Bool {
        let values = [
            option.displayName,
            option.extendedLanguageTag ?? "",
            option.locale?.identifier ?? "",
            option.locale?.localizedString(forLanguageCode: option.locale?.language.languageCode?.identifier ?? "") ?? ""
        ]
        let joined = values.joined(separator: " ").lowercased()
        return joined.contains("zh")
            || joined.contains("chi")
            || joined.contains("zho")
            || joined.contains("中文")
            || joined.contains("繁體")
            || joined.contains("繁体")
            || joined.contains("簡體")
            || joined.contains("简体")
            || joined.contains("chinese")
    }

    private func handlePlayback(_ command: RemoteCommand) {
        mediaState.apply(command, restartOnSelect: canRestartFromBeginningWithSelect)

        if mediaState.pendingSeekOffset != 0 {
            let current = player.currentTime().seconds
            let target = max(0, current + mediaState.pendingSeekOffset)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }

        if mediaState.shouldRestartFromBeginning {
            canRestartFromBeginningWithSelect = false
            player.seek(to: .zero)
            recordPlaybackProgress(time: 0, force: true)
            showPlayerHUD(allowRestart: false)
            player.play()
            isDanmakuClockRunning = true
            return
        }

        if command == .playPause || command == .select {
            showPlayerHUD(allowRestart: false)
            if mediaState.isPlaying {
                player.play()
                isDanmakuClockRunning = true
            } else {
                player.pause()
                isDanmakuClockRunning = false
            }
        }
    }

    private func showPlayerHUD(allowRestart: Bool = false) {
        isPlayerHUDVisible = true
        canRestartFromBeginningWithSelect = allowRestart
        hidePlayerHUDTask?.cancel()
        hidePlayerHUDTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.isPlayerHUDVisible = false
            self?.canRestartFromBeginningWithSelect = false
        }
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else {
            return
        }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateDanmaku(time: time.seconds)
            }
        }
    }

    func updateYouTubeDanmaku(time: Double, isPlaying: Bool) {
        guard currentYouTubeVideoID != nil else {
            return
        }
        isDanmakuClockRunning = isPlaying
        updateDanmaku(time: time)
    }

    private func updateDanmaku(time: Double) {
        danmakuPlaybackTime = time
        danmakuPlaybackDate = Date()
        visibleDanmaku = comments
            .filter { time >= $0.time && time - $0.time < 8.0 }
            .suffix(12)
        recordPlaybackProgress(time: time)
    }

    private func resumeTime(for mediaID: String) -> Double {
        watchHistory.first { $0.mediaID == mediaID }?.resumeTimeSeconds ?? 0
    }

    private func watchMediaID(for episode: AnimeEpisode) -> String {
        [
            "anime",
            episode.identity.providerID,
            episode.identity.subjectID,
            episode.identity.episodeID
        ].joined(separator: ":")
    }

    private func recordPlaybackProgress(force: Bool = false) {
        recordPlaybackProgress(time: player.currentTime().seconds, force: force)
    }

    private func recordPlaybackProgress(time: Double, force: Bool = false) {
        guard let episode = currentPlayingEpisode,
              time.isFinite
        else {
            return
        }
        let mediaID = watchMediaID(for: episode)
        guard force || mediaID != lastRecordedMediaID || abs(time - lastRecordedTime) >= 5 else {
            return
        }
        lastRecordedMediaID = mediaID
        lastRecordedTime = time
        let duration = player.currentItem?.duration.seconds
        NotificationCenter.default.post(
            name: .tvShellRecordWatch,
            object: nil,
            userInfo: [
                WatchHistoryNotification.entryKey: WatchHistoryEntry(
                    title: currentTitle?.title ?? episode.title,
                    subtitle: episode.title,
                    kind: .anime,
                    mediaID: mediaID,
                    resumeTimeSeconds: max(0, time),
                    durationSeconds: duration?.isFinite == true ? duration : nil
                )
            ]
        )
    }
}

private struct AnimeStreamPickerView: View {
    let episodeTitle: String
    let choices: [AnimeStreamCandidate]
    let focusedIndex: Int
    let metrics: TVMetrics

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24 * metrics.scale) {
                Text("選擇播放影片")
                    .font(.system(size: 52 * metrics.scale, weight: .bold))
                Text(episodeTitle)
                    .font(.system(size: 28 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text("上下選擇，OK 確認並記住，Back 取消")
                    .font(.system(size: 22 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 14 * metrics.scale) {
                            ForEach(Array(choices.enumerated()), id: \.element.url.absoluteString) { index, stream in
                                VStack(alignment: .leading, spacing: 8 * metrics.scale) {
                                    Text(stream.headers["title"] ?? stream.quality)
                                        .font(.system(size: 28 * metrics.scale, weight: .bold))
                                        .lineLimit(2)
                                    Text([stream.headers["channel"], stream.quality]
                                        .compactMap { $0 }
                                        .joined(separator: " · "))
                                        .font(.system(size: 21 * metrics.scale, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.66))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(22 * metrics.scale)
                                .liquidGlassCard(isFocused: index == focusedIndex, cornerRadius: 22 * metrics.scale)
                                .scaleEffect(index == focusedIndex ? 1.02 : 1)
                                .id("anime-stream-choice-\(index)")
                            }
                        }
                        .padding(8 * metrics.scale)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: focusedIndex) { _, index in
                        withAnimation(TVMotion.focus) {
                            scrollProxy.scrollTo("anime-stream-choice-\(index)", anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: 1_120 * metrics.scale, maxHeight: 760 * metrics.scale, alignment: .topLeading)
            .padding(38 * metrics.scale)
            .liquidGlassCard(isFocused: true, cornerRadius: 34 * metrics.scale)
        }
    }
}

private struct AnimeTitleCard: View {
    let title: AnimeSearchResult
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        let posterWidth = 166 * metrics.scale
        let posterHeight = 236 * metrics.scale

        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: posterWidth, height: posterHeight)

            if let coverURL = title.coverURL {
                AsyncImage(url: coverURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ZStack {
                        Color.white.opacity(0.06)
                        ProgressView()
                            .controlSize(.large)
                    }
                    .frame(width: posterWidth, height: posterHeight)
                }
                .frame(width: posterWidth, height: posterHeight)
                .clipped()
            } else {
                Text(String(title.title.prefix(1)))
                    .font(.system(size: 56 * metrics.scale, weight: .heavy, design: .rounded))
                    .frame(width: posterWidth, height: posterHeight)
                    .foregroundStyle(.white.opacity(0.74))
            }

            VStack {
                Spacer()
                Text(title.title)
                    .font(.system(size: 18 * metrics.scale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.66)
                    .foregroundStyle(.white)
                    .padding(10 * metrics.scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
            }
            .frame(width: posterWidth, height: posterHeight)
        }
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16 * metrics.scale, style: .continuous)
                .stroke(.white.opacity(isFocused ? 0.96 : 0.08), lineWidth: isFocused ? 4 : 1)
        )
        .shadow(color: .black.opacity(isFocused ? 0.36 : 0.16), radius: isFocused ? 18 : 6, x: 0, y: isFocused ? 10 : 4)
        .scaleEffect(isFocused ? 1.045 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

private struct EpisodeCard: View {
    let episode: AnimeEpisode
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            Text(String(format: "%02d", episode.number))
                .font(.system(size: 34 * metrics.scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text(episode.title)
                .font(.system(size: 32 * metrics.scale, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 138 * metrics.scale, alignment: .leading)
        .padding(26 * metrics.scale)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 26 * metrics.scale)
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

private struct TorrentDownloadRow: View {
    let item: TorrentCachedDownload
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 20 * metrics.scale) {
            VStack(alignment: .leading, spacing: 8 * metrics.scale) {
                Text(item.title)
                    .font(.system(size: 30 * metrics.scale, weight: .bold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 23 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: 18 * metrics.scale)

            Text(item.megabytesText)
                .font(.system(size: 25 * metrics.scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(.horizontal, 24 * metrics.scale)
        .padding(.vertical, 20 * metrics.scale)
        .frame(maxWidth: .infinity, minHeight: 94 * metrics.scale, alignment: .leading)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 22 * metrics.scale)
        .scaleEffect(isFocused ? 1.015 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

struct DanmakuOverlay: View {
    let comments: [DanmakuComment]
    let currentTime: Double
    let sampleDate: Date
    let isClockRunning: Bool
    let settings: DanmakuDisplaySettings
    let metrics: TVMetrics

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let interpolatedTime = currentTime + (isClockRunning ? timeline.date.timeIntervalSince(sampleDate) : 0)
                let visibleComments = Array(comments.suffix(settings.density))
                ForEach(Array(visibleComments.enumerated()), id: \.element.stableIdentity) { index, comment in
                    let age = max(0, interpolatedTime - comment.time)
                    let lifetime = 4.2 / settings.speedScale
                    let progress = min(max(age / lifetime, 0), 1)
                    let travel = proxy.size.width + 620 * metrics.scale
                    Text(verbatim: comment.text)
                        .modifier(DanmakuTextStyle(settings: settings, metrics: metrics))
                        .foregroundStyle(.white.opacity(settings.opacity))
                        .shadow(color: .black.opacity(0.92), radius: 8, x: 0, y: 3)
                        .padding(.horizontal, 20 * metrics.scale)
                        .padding(.vertical, 8 * metrics.scale)
                        .background(.black.opacity(0.22 * settings.opacity), in: Capsule())
                        .offset(
                            x: proxy.size.width - CGFloat(progress) * CGFloat(travel),
                            y: CGFloat(index % settings.density) * CGFloat(54 * metrics.scale * settings.sizeScale)
                        )
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 78 * metrics.scale)
        .padding(.leading, 78 * metrics.scale)
        .drawingGroup()
    }
}

extension DanmakuComment {
    var stableIdentity: String {
        "\(time)-\(text)-\(colorHex)-\(mode.rawValue)"
    }
}

struct DanmakuTextStyle: ViewModifier {
    let settings: DanmakuDisplaySettings
    let metrics: TVMetrics

    func body(content: Content) -> some View {
        content.font(.system(size: 31 * metrics.scale * settings.sizeScale, weight: .bold))
    }
}

private struct AnimePlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

private struct InternalVLCPlayerSurface: NSViewRepresentable {
    let url: URL
    let headers: [String: String]
    let onStatus: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onStatus: onStatus)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        context.coordinator.play(url: url, headers: headers, in: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.updateStatusHandler(onStatus)
        context.coordinator.play(url: url, headers: headers, in: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        private var player: NSObject?
        private var media: NSObject?
        private var currentURL: URL?
        private var currentHeaders: [String: String] = [:]
        private var statusHandler: @MainActor (String) -> Void
        private var commandObserver: NSObjectProtocol?
        private var isPlaying = false

        init(onStatus: @escaping @MainActor (String) -> Void) {
            statusHandler = onStatus
            super.init()
            commandObserver = NotificationCenter.default.addObserver(
                forName: .tvShellRuntimeCommand,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handle(command)
                }
            }
        }

        deinit {
            MainActor.assumeIsolated {
                player?.perform(NSSelectorFromString("stop"))
                if let commandObserver {
                    NotificationCenter.default.removeObserver(commandObserver)
                }
            }
        }

        func updateStatusHandler(_ onStatus: @escaping @MainActor (String) -> Void) {
            statusHandler = onStatus
        }

        func play(url: URL, headers: [String: String], in view: NSView) {
            if currentURL == url, currentHeaders == headers, player != nil {
                return
            }
            currentURL = url
            currentHeaders = headers

            guard loadVLCKitIfNeeded() else {
                report("內建 VLC 引擎尚未打包：請把 VLCKit.framework 放到 app 的 Contents/Frameworks。")
                return
            }
            guard let playerClass = vlcClass(named: "VLCMediaPlayer"),
                  let mediaClass = vlcClass(named: "VLCMedia"),
                  let newMedia = mediaClass.perform(NSSelectorFromString("mediaWithURL:"), with: url)?.takeUnretainedValue() as? NSObject
            else {
                report("內建 VLC 引擎載入失敗：找不到 VLCMediaPlayer 或 VLCMedia。")
                return
            }

            let initializedPlayer = playerClass.init()
            player?.perform(NSSelectorFromString("stop"))
            player = initializedPlayer
            media = newMedia
            if headers.isEmpty == false {
                let options = vlcOptions(from: headers)
                if options.isEmpty == false {
                    newMedia.perform(NSSelectorFromString("addOptions:"), with: options as NSDictionary)
                }
            }
            initializedPlayer.setValue(view, forKey: "drawable")
            initializedPlayer.setValue(newMedia, forKey: "media")
            initializedPlayer.perform(NSSelectorFromString("play"))
            isPlaying = true
            report("內建 VLC 播放中：\(url.lastPathComponent)")
        }

        func stop() {
            player?.perform(NSSelectorFromString("stop"))
            player = nil
            media = nil
            currentURL = nil
            currentHeaders = [:]
            isPlaying = false
        }

        private func handle(_ command: RemoteCommand) {
            switch command {
            case .playPause, .select:
                togglePlayback()
            case .left, .rewind:
                seek(by: -15)
            case .right, .fastForward:
                seek(by: 15)
            case .back:
                player?.perform(NSSelectorFromString("stop"))
                isPlaying = false
            default:
                break
            }
        }

        private func togglePlayback() {
            if isPlaying {
                player?.perform(NSSelectorFromString("pause"))
                isPlaying = false
                report("內建 VLC 已暫停")
            } else {
                player?.perform(NSSelectorFromString("play"))
                isPlaying = true
                report("內建 VLC 播放中")
            }
        }

        private func seek(by seconds: Int) {
            guard let player else {
                return
            }
            let current = (player.value(forKey: "time") as? NSNumber)?.intValue ?? 0
            player.setValue(NSNumber(value: max(0, current + seconds * 1000)), forKey: "time")
            report(seconds > 0 ? "內建 VLC 快轉 15 秒" : "內建 VLC 倒退 15 秒")
        }

        private func loadVLCKitIfNeeded() -> Bool {
            if vlcClass(named: "VLCMediaPlayer") != nil {
                return true
            }
            let candidates = [
                Bundle.main.privateFrameworksURL?.appendingPathComponent("VLCKit.framework"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VLCKit.framework"),
                URL(fileURLWithPath: "/Library/Frameworks/VLCKit.framework"),
                URL(fileURLWithPath: "/Applications/VLC.app/Contents/Frameworks/VLCKit.framework")
            ].compactMap(\.self)

            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                if Bundle(url: url)?.load() == true, vlcClass(named: "VLCMediaPlayer") != nil {
                    return true
                }
            }
            return false
        }

        private func vlcClass(named name: String) -> NSObject.Type? {
            (NSClassFromString(name) ?? NSClassFromString("VLCKit.\(name)")) as? NSObject.Type
        }

        private func vlcOptions(from headers: [String: String]) -> [String: String] {
            var options: [String: String] = [:]
            if let userAgent = headers["User-Agent"] ?? headers["user-agent"] {
                options[":http-user-agent"] = userAgent
            }
            if let referer = headers["Referer"] ?? headers["referer"] {
                options[":http-referrer"] = referer
            }
            if let cookie = headers["Cookie"] ?? headers["cookie"], cookie.isEmpty == false {
                options[":http-forward-cookies"] = "true"
            }
            return options
        }

        private func report(_ status: String) {
            statusHandler(status)
        }
    }
}
