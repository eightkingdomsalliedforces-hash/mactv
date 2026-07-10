import AVKit
@preconcurrency import AVFoundation
import SwiftUI

public struct BilibiliRuntimeView: View {
    public let app: TVAppProfile
    @EnvironmentObject private var appState: AppState
    @StateObject private var controller = BilibiliRuntimeController()

    public init(app: TVAppProfile) {
        self.app = app
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ZStack {
                TVControlBackdrop()

                switch controller.state.phase {
                case .browsing:
                    seasonBrowser(metrics: metrics, size: proxy.size)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .detail:
                    detailView(metrics: metrics, size: proxy.size)
                        .transition(.opacity.combined(with: .scale(scale: 1.015)))
                case .playing:
                    player(metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }

                if controller.isKeyboardVisible {
                    VirtualKeyboardView(
                        title: "搜尋 Bilibili 番劇",
                        state: controller.keyboardState,
                        metrics: metrics
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(20)
                }
            }
            .animation(TVMotion.runtime, value: controller.state.phase)
        .foregroundStyle(.white)
        .onAppear {
            controller.updateCredentials(appState.bilibiliCredentials)
            controller.updateSeasonColumns(Self.seasonColumns(metrics: metrics, size: proxy.size, mode: controller.contentMode))
            controller.updateEpisodeColumns(Self.episodeColumns(metrics: metrics, size: proxy.size))
        }
            .onChange(of: proxy.size) { _, size in
                let nextMetrics = TVMetrics(size: size)
                controller.updateSeasonColumns(Self.seasonColumns(metrics: nextMetrics, size: size, mode: controller.contentMode))
                controller.updateEpisodeColumns(Self.episodeColumns(metrics: nextMetrics, size: size))
            }
        }
        .task {
            controller.updateCredentials(appState.bilibiliCredentials)
            controller.updateWatchHistory(appState.watchingHistory)
            await controller.loadHome()
            if let entry = appState.consumePendingWatchHistory(kind: .bilibili) {
                controller.resume(from: entry)
            }
        }
        .onChange(of: appState.bilibiliCredentials) { _, credentials in
            controller.updateCredentials(credentials)
        }
        .onChange(of: appState.watchingHistory) { _, history in
            controller.updateWatchHistory(history)
        }
        .onChange(of: controller.state.phase) { _, phase in
            setStatusClockHidden(phase == .playing)
        }
        .onDisappear {
            setStatusClockHidden(false)
        }
    }

    private static func seasonColumns(metrics: TVMetrics, size: CGSize, mode: BilibiliContentMode) -> Int {
        adaptiveColumns(
            availableWidth: size.width - metrics.horizontalPadding * 2,
            minimumWidth: (mode == .video ? 340 : 210) * metrics.scale,
            spacing: 28 * metrics.scale
        )
    }

    private static func episodeColumns(metrics: TVMetrics, size: CGSize) -> Int {
        adaptiveColumns(
            availableWidth: size.width - metrics.horizontalPadding * 2,
            minimumWidth: 190 * metrics.scale,
            spacing: 20 * metrics.scale
        )
    }

    private static func adaptiveColumns(availableWidth: Double, minimumWidth: Double, spacing: Double) -> Int {
        max(1, Int((max(availableWidth, minimumWidth) + spacing) / (minimumWidth + spacing)))
    }

    private func seasonBrowser(metrics: TVMetrics, size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 32 * metrics.scale) {
                    header(metrics: metrics, title: app.name, subtitle: controller.statusText)
                        .id("bilibili-browser-top")

                    BilibiliModeSwitcher(mode: controller.contentMode, metrics: metrics)

                    BilibiliSectionGrid(
                        title: "番劇",
                        items: controller.bangumiItems,
                        baseIndex: controller.bangumiStartIndex,
                        focusedIndex: controller.state.focusedSeasonIndex,
                        metrics: metrics
                    )

                    BilibiliSectionGrid(
                        title: "一般影片",
                        items: controller.videoItems,
                        baseIndex: controller.videoStartIndex,
                        focusedIndex: controller.state.focusedSeasonIndex,
                        metrics: metrics
                    )

                    Text("方向鍵選內容，OK 進入詳情，播放/暫停鍵切換全部、番劇、一般影片，Menu 搜尋，Back 或 Home 返回。登入 Cookie 可在設定的 credentials.json 保存。")
                        .font(.system(size: 22 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 60 * metrics.scale)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.state.focusedSeasonIndex) { _, index in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("bilibili-season-\(index)", anchor: .center)
                }
                let focusedMode: BilibiliContentMode = controller.focusedSeason?.itemKind == .video ? .video : .bangumi
                controller.updateSeasonColumns(Self.seasonColumns(metrics: metrics, size: size, mode: focusedMode))
            }
            .onChange(of: controller.contentMode) { _, mode in
                controller.updateSeasonColumns(Self.seasonColumns(metrics: metrics, size: size, mode: mode))
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("bilibili-browser-top", anchor: .top)
                }
            }
            .onChange(of: controller.seasons.count) { _, _ in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("bilibili-browser-top", anchor: .top)
                }
            }
        }
    }

    private func detailView(metrics: TVMetrics, size: CGSize) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30 * metrics.scale) {
                    if let detail = controller.detail {
                        HStack(alignment: .top, spacing: 34 * metrics.scale) {
                            BilibiliPosterImage(url: detail.coverURL, title: detail.title, width: 230 * metrics.scale, height: 322 * metrics.scale)

                            VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                                Text(detail.title)
                                    .font(.system(size: 64 * metrics.scale, weight: .bold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.72)
                                Text(controller.detailMetaText)
                                    .font(.system(size: 25 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(2)
                                Text(detail.evaluate ?? detail.subtitle ?? "Bilibili 番劇")
                                    .font(.system(size: 24 * metrics.scale, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        header(metrics: metrics, title: "Bilibili", subtitle: controller.statusText)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190 * metrics.scale), spacing: 20 * metrics.scale)],
                        alignment: .leading,
                        spacing: 22 * metrics.scale
                    ) {
                        ForEach(Array(controller.episodes.enumerated()), id: \.element.id) { index, episode in
                            BilibiliEpisodeCard(
                                episode: episode,
                                isFocused: index == controller.state.focusedEpisodeIndex,
                                metrics: metrics
                            )
                            .id("bilibili-episode-\(index)")
                        }
                    }

                    Text("OK 播放目前項目，Back 回列表，Menu 搜尋其他內容。需要會員、登入、地區或版權限制的內容會顯示 Bilibili 回傳錯誤。")
                        .font(.system(size: 22 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 60 * metrics.scale)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.state.focusedEpisodeIndex) { _, index in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("bilibili-episode-\(index)", anchor: .center)
                }
            }
        }
    }

    private func player(metrics: TVMetrics) -> some View {
        ZStack(alignment: .bottomLeading) {
            BilibiliPlayerSurface(player: controller.player)
                .ignoresSafeArea()

            DanmakuOverlay(
                comments: controller.visibleDanmaku,
                currentTime: controller.danmakuPlaybackTime,
                sampleDate: controller.danmakuPlaybackDate,
                isClockRunning: controller.isDanmakuClockRunning,
                settings: appState.danmakuDisplaySettings,
                metrics: metrics
            )
            .zIndex(3)

            if controller.isPlayerHUDVisible {
                VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                    Text(controller.playingTitle)
                        .font(.system(size: 38 * metrics.scale, weight: .bold))
                        .lineLimit(2)
                    Text(controller.statusText)
                        .font(.system(size: 22 * metrics.scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                .padding(28 * metrics.scale)
                .liquidGlassCard(isFocused: true, cornerRadius: 22 * metrics.scale)
                .padding(50 * metrics.scale)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(.black)
    }

    private func header(metrics: TVMetrics, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            Text(title)
                .font(.system(size: 76 * metrics.scale, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.system(size: 28 * metrics.scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
        }
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
final class BilibiliRuntimeController: ObservableObject {
    @Published private(set) var state = BilibiliRuntimeState()
    @Published private(set) var seasons: [BilibiliSeason] = []
    @Published private(set) var detail: BilibiliSeasonDetail?
    @Published private(set) var statusText = "正在載入 Bilibili..."
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var isPlayerHUDVisible = false
    @Published private(set) var keyboardState = VirtualKeyboardState(text: "间谍过家家", layout: .zhuyin)
    @Published private(set) var contentMode: BilibiliContentMode = .all
    @Published private(set) var visibleDanmaku: [DanmakuComment] = []
    @Published private(set) var danmakuPlaybackTime: Double = 0
    @Published private(set) var danmakuPlaybackDate = Date()
    @Published private(set) var isDanmakuClockRunning = false
    let player = AVPlayer()

    private var provider: any BilibiliBangumiProviding
    private var credentials: BilibiliCredentials = .environment()
    private var seasonColumns = 5
    private var episodeColumns = 6
    private var currentQuery = ""
    private var watchHistory: [WatchHistoryEntry] = []
    private var mediaState = MediaControlState()
    private var currentEpisode: BilibiliEpisode?
    private var currentStream: BilibiliPlaybackStream?
    private var comments: [DanmakuComment] = []
    private var lastRecordedMediaID: String?
    private var lastRecordedTime: Double = -1
    private var hidePlayerHUDTask: Task<Void, Never>?
    private nonisolated(unsafe) var timeObserver: Any?
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private nonisolated(unsafe) var itemEndObserver: NSObjectProtocol?
    private nonisolated(unsafe) var itemObserver: NSKeyValueObservation?

    init(provider: any BilibiliBangumiProviding = BilibiliProviderFactory.defaultProvider()) {
        self.provider = provider
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

    func updateCredentials(_ credentials: BilibiliCredentials) {
        guard self.credentials != credentials else {
            return
        }
        self.credentials = credentials
        provider = BilibiliProviderFactory.defaultProvider(credentials: credentials)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        itemObserver?.invalidate()
        hidePlayerHUDTask?.cancel()
    }

    var episodes: [BilibiliEpisode] {
        detail?.episodes ?? []
    }

    var bangumiItems: [BilibiliSeason] {
        guard contentMode != .video else {
            return []
        }
        return seasons.filter { $0.itemKind == .bangumi }
    }

    var videoItems: [BilibiliSeason] {
        guard contentMode != .bangumi else {
            return []
        }
        return seasons.filter { $0.itemKind == .video }
    }

    var visibleSeasons: [BilibiliSeason] {
        switch contentMode {
        case .all:
            return seasons.filter { $0.itemKind == .bangumi } + seasons.filter { $0.itemKind == .video }
        case .bangumi:
            return seasons.filter { $0.itemKind == .bangumi }
        case .video:
            return seasons.filter { $0.itemKind == .video }
        }
    }

    var bangumiStartIndex: Int {
        0
    }

    var videoStartIndex: Int {
        bangumiItems.count
    }

    var detailMetaText: String {
        guard let detail else {
            return statusText
        }
        return [
            detail.subtitle,
            detail.ratingScore.map { String(format: "%.1f 分", $0) },
            detail.views.map { "\($0) 次觀看" },
            detail.danmaku.map { "\($0) 條彈幕" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var focusedSeason: BilibiliSeason? {
        let items = visibleSeasons
        guard items.indices.contains(state.focusedSeasonIndex) else {
            return nil
        }
        return items[state.focusedSeasonIndex]
    }

    var focusedEpisode: BilibiliEpisode? {
        guard episodes.indices.contains(state.focusedEpisodeIndex) else {
            return nil
        }
        return episodes[state.focusedEpisodeIndex]
    }

    var playingTitle: String {
        let episodeText = currentEpisode.map { "第 \($0.number) 話 \($0.longTitle.isEmpty ? $0.title : $0.longTitle)" } ?? "Bilibili"
        return [detail?.title, episodeText].compactMap { $0 }.joined(separator: " · ")
    }

    func updateSeasonColumns(_ columns: Int) {
        seasonColumns = max(1, columns)
    }

    func updateEpisodeColumns(_ columns: Int) {
        episodeColumns = max(1, columns)
    }

    func updateWatchHistory(_ history: [WatchHistoryEntry]) {
        watchHistory = history
    }

    func resume(from entry: WatchHistoryEntry) {
        guard entry.kind == .bilibili,
              let mediaID = entry.mediaID,
              mediaID.hasPrefix("bilibili:video:")
        else {
            statusText = "這筆 Bilibili 紀錄缺少可恢復的影片識別碼。"
            return
        }
        let components = mediaID.split(separator: ":")
        guard components.count >= 4,
              let cid = Int(components[3])
        else {
            statusText = "這筆 Bilibili 紀錄格式不完整。"
            return
        }
        let episode = BilibiliEpisode(
            id: cid,
            cid: cid,
            bvid: String(components[2]),
            title: entry.subtitle ?? "續播",
            longTitle: entry.subtitle ?? "",
            number: 1
        )
        detail = BilibiliSeasonDetail(id: cid, title: entry.title, episodes: [episode])
        state = BilibiliRuntimeState(seasonCount: 1, episodeCount: 1)
        state.openDetail()
        statusText = "已從 \(entry.resumeTimeLabel) 恢復 Bilibili 播放"
        play(episode)
    }

    func loadHome() async {
        do {
            seasons = try await provider.home()
            state.updateSeasonCount(visibleSeasons.count)
            statusText = seasons.isEmpty ? "Bilibili 沒有回傳推薦。" : "Bilibili 推薦 · \(contentMode.title) · 已載入 \(visibleSeasons.count) 部"
        } catch {
            seasons = []
            state.updateSeasonCount(0)
            statusText = "Bilibili 載入失敗：\(error.localizedDescription)"
        }
    }

    private func search(keyword: String) async {
        do {
            currentQuery = keyword
            seasons = try await provider.search(keyword: keyword)
            state = BilibiliRuntimeState(seasonCount: visibleSeasons.count)
            let requestKeyword = BilibiliSearchNormalizer.simplified(keyword)
            let conversion = requestKeyword == keyword ? "" : " · 已用簡體搜尋：\(requestKeyword)"
            statusText = visibleSeasons.isEmpty ? "Bilibili 找不到：\(keyword)\(conversion)" : "Bilibili 搜尋：\(keyword)\(conversion) · \(contentMode.title) · \(visibleSeasons.count) 部"
        } catch {
            seasons = []
            state = BilibiliRuntimeState(seasonCount: 0)
            statusText = "Bilibili 搜尋失敗：\(error.localizedDescription)"
        }
    }

    private func loadDetail(for season: BilibiliSeason) {
        statusText = "正在載入：\(season.title)"
        Task {
            do {
            detail = try await provider.detail(item: season)
                state.updateEpisodeCount(episodes.count)
                state.openDetail()
                statusText = "已載入 \(episodes.count) 集 · OK 播放"
            } catch {
                statusText = "番劇詳情載入失敗：\(error.localizedDescription)"
            }
        }
    }

    private func play(_ episode: BilibiliEpisode) {
        currentEpisode = episode
        statusText = "正在解析 Bilibili 播放地址..."
        Task {
            do {
                let stream = try await provider.playback(episode: episode)
                currentStream = stream
                state.openPlayer()
                load(stream: stream, episode: episode)
                await loadDanmaku(for: episode)
                showPlayerHUD()
            } catch {
                statusText = "Bilibili 無法播放：\(error.localizedDescription)"
                showPlayerHUD()
            }
        }
    }

    private func load(stream: BilibiliPlaybackStream, episode: BilibiliEpisode) {
        let resume = resumeTime(for: episode)
        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        let item = AVPlayerItem(asset: asset)
        itemObserver?.invalidate()
        itemObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    if resume > 1 {
                        await self?.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
                    }
                    self?.player.play()
                    self?.statusText = "播放/暫停控制播放，左右快轉倒退，Back 回選集。"
                case .failed:
                    self?.player.pause()
                    self?.state.closePlayer()
                    self?.statusText = item.error?.localizedDescription ?? "Bilibili 影片載入失敗，可能需要登入、會員或地區權限。"
                case .unknown:
                    self?.statusText = "正在載入 Bilibili 影片..."
                @unknown default:
                    self?.statusText = "Bilibili 影片狀態變更。"
                }
            }
        }
        player.replaceCurrentItem(with: item)
        mediaState = MediaControlState(isPlaying: true)
        isDanmakuClockRunning = true
        installTimeObserverIfNeeded()
        installItemEndObserver(for: item)
        recordPlaybackProgress(time: resume, force: true)
    }

    private func handle(_ command: RemoteCommand) {
        if isKeyboardVisible {
            handleKeyboard(command)
            return
        }

        if command == .menu {
            keyboardState = VirtualKeyboardState(text: currentQuery.isEmpty ? "间谍过家家" : currentQuery, layout: .zhuyin)
            isKeyboardVisible = true
            statusText = "Bilibili 搜尋"
            return
        }

        switch state.phase {
        case .browsing:
            if command == .playPause {
                toggleContentMode()
                return
            }
            if command == .back {
                NotificationCenter.default.post(name: .tvShellRequestLauncher, object: nil)
                return
            }
            if command == .select, let focusedSeason {
                loadDetail(for: focusedSeason)
                return
            }
            state.applyBrowsing(command, columns: seasonColumns)
        case .detail:
            if command == .back {
                state.resetToBrowsing()
                return
            }
            if command == .select, let focusedEpisode {
                play(focusedEpisode)
                return
            }
            state.applyDetail(command, columns: episodeColumns)
        case .playing:
            if command == .back {
                player.pause()
                isDanmakuClockRunning = false
                state.closePlayer()
                return
            }
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
            statusText = "正在搜尋：\(query)..."
            Task { await search(keyword: query) }
        case .cancelled:
            isKeyboardVisible = false
            statusText = "已關閉搜尋"
        }
    }

    private func handlePlayback(_ command: RemoteCommand) {
        mediaState.apply(command)
        if mediaState.pendingSeekOffset != 0 {
            let target = max(0, player.currentTime().seconds + mediaState.pendingSeekOffset)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
        if mediaState.shouldRestartFromBeginning {
            player.seek(to: .zero)
            player.play()
            return
        }
        if command == .playPause || command == .select {
            showPlayerHUD()
        }
        mediaState.isPlaying ? player.play() : player.pause()
        isDanmakuClockRunning = mediaState.isPlaying
    }

    private func toggleContentMode() {
        contentMode = contentMode.next
        state = BilibiliRuntimeState(seasonCount: visibleSeasons.count)
        statusText = "Bilibili：已切換到\(contentMode.title) · \(visibleSeasons.count) 部"
    }

    private func resumeTime(for episode: BilibiliEpisode) -> Double {
        watchHistory.first { $0.mediaID == watchMediaID(for: episode) }?.resumeTimeSeconds ?? 0
    }

    private func watchMediaID(for episode: BilibiliEpisode) -> String {
        if let bvid = episode.bvid, let cid = episode.cid {
            return "bilibili:video:\(bvid):\(cid)"
        }
        return "bilibili:ep:\(episode.id)"
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else {
            return
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.recordPlaybackProgress(time: time.seconds)
                self?.updateDanmaku(time: time.seconds)
            }
        }
    }

    private func loadDanmaku(for episode: BilibiliEpisode) async {
        do {
            comments = try await provider.danmaku(episode: episode)
            updateDanmaku(time: player.currentTime().seconds)
            statusText = "播放/暫停控制播放，左右快轉倒退，Back 回選集 · Bilibili 彈幕 \(comments.count) 條"
        } catch {
            comments = []
            visibleDanmaku = []
            statusText = "播放/暫停控制播放，左右快轉倒退，Back 回選集 · Bilibili 彈幕載入失敗"
        }
    }

    private func updateDanmaku(time: Double) {
        danmakuPlaybackTime = time
        danmakuPlaybackDate = Date()
        isDanmakuClockRunning = mediaState.isPlaying
        visibleDanmaku = comments
            .filter { time >= $0.time && time - $0.time < 8.0 }
            .suffix(12)
    }

    private func recordPlaybackProgress(time: Double, force: Bool = false) {
        guard let currentEpisode,
              time.isFinite
        else {
            return
        }
        let mediaID = watchMediaID(for: currentEpisode)
        guard force || mediaID != lastRecordedMediaID || abs(time - lastRecordedTime) >= 5 else {
            return
        }
        lastRecordedMediaID = mediaID
        lastRecordedTime = time
        NotificationCenter.default.post(
            name: .tvShellRecordWatch,
            object: nil,
            userInfo: [
                WatchHistoryNotification.entryKey: WatchHistoryEntry(
                    title: detail?.title ?? "Bilibili 番劇",
                    subtitle: "\(currentEpisode.title) · \(currentEpisode.longTitle.isEmpty ? "Bilibili" : currentEpisode.longTitle)",
                    kind: .bilibili,
                    mediaID: mediaID,
                    resumeTimeSeconds: max(0, time),
                    durationSeconds: currentStream?.durationSeconds
                )
            ]
        )
    }

    private func showPlayerHUD() {
        isPlayerHUDVisible = true
        hidePlayerHUDTask?.cancel()
        hidePlayerHUDTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.isPlayerHUDVisible = false
        }
    }

    private func installItemEndObserver(for item: AVPlayerItem) {
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
                    self.player.pause()
                    self.mediaState = MediaControlState(isPlaying: false)
                    self.statusText = "Bilibili 播放很快結束，可能是登入、會員、地區限制，或此影片沒有可用直連。請在設定重載 Cookie 後再試。"
                    self.state.closePlayer()
                }
            }
        }
    }
}

private struct BilibiliModeSwitcher: View {
    let mode: BilibiliContentMode
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 14 * metrics.scale) {
            ForEach(BilibiliContentMode.allCases, id: \.self) { item in
                Text(item.title)
                    .font(.system(size: 24 * metrics.scale, weight: .heavy))
                    .foregroundStyle(item == mode ? .black.opacity(0.82) : .white.opacity(0.72))
                    .padding(.horizontal, 26 * metrics.scale)
                    .padding(.vertical, 14 * metrics.scale)
                    .background(item == mode ? .white.opacity(0.92) : .white.opacity(0.12), in: Capsule())
            }
            Text("播放/暫停鍵切換")
                .font(.system(size: 20 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.54))
        }
    }
}

private struct BilibiliSectionGrid: View {
    let title: String
    let items: [BilibiliSeason]
    let baseIndex: Int
    let focusedIndex: Int
    let metrics: TVMetrics

    var body: some View {
        if items.isEmpty == false {
            VStack(alignment: .leading, spacing: 18 * metrics.scale) {
                Text(title)
                    .font(.system(size: 38 * metrics.scale, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.88))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: gridMinimumWidth * metrics.scale), spacing: 28 * metrics.scale)],
                    alignment: .leading,
                    spacing: 34 * metrics.scale
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, season in
                        let absoluteIndex = baseIndex + offset
                        BilibiliSeasonCard(
                            season: season,
                            isFocused: absoluteIndex == focusedIndex,
                            metrics: metrics
                        )
                        .id("bilibili-season-\(absoluteIndex)")
                    }
                }
            }
        }
    }

    private var gridMinimumWidth: Double {
        items.first?.itemKind == .video ? 340 : 210
    }
}

private struct BilibiliSeasonCard: View {
    let season: BilibiliSeason
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        let isVideo = season.itemKind == .video
        let width = (isVideo ? 330 : 190) * metrics.scale
        let height = (isVideo ? 186 : 268) * metrics.scale
        VStack(alignment: .leading, spacing: 12 * metrics.scale) {
            BilibiliPosterImage(url: season.coverURL, title: season.title, width: width, height: height)
                .overlay(alignment: .topLeading) {
                    if let badge = season.badge {
                        Text(badge)
                            .font(.system(size: 15 * metrics.scale, weight: .bold))
                            .padding(.horizontal, 9 * metrics.scale)
                            .padding(.vertical, 5 * metrics.scale)
                            .background(.pink.opacity(0.78), in: Capsule())
                            .padding(9 * metrics.scale)
                    }
                }
            Text(season.title)
                .font(.system(size: 23 * metrics.scale, weight: .bold))
                .lineLimit(2)
            Text(season.totalText ?? season.subtitle ?? "Bilibili")
                .font(.system(size: 17 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .scaleEffect(isFocused ? 1.08 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.48 : 0.18), radius: isFocused ? 24 : 8, x: 0, y: isFocused ? 18 : 6)
        .animation(TVMotion.focus, value: isFocused)
        .accessibilityLabel(season.title)
    }
}

private struct BilibiliEpisodeCard: View {
    let episode: BilibiliEpisode
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * metrics.scale) {
            Text(String(format: "%02d", episode.number))
                .font(.system(size: 28 * metrics.scale, weight: .heavy))
                .foregroundStyle(.white.opacity(0.82))
            Text(episode.longTitle.isEmpty ? "第 \(episode.title) 話" : episode.longTitle)
                .font(.system(size: 22 * metrics.scale, weight: .bold))
                .lineLimit(3)
                .minimumScaleFactor(0.74)
            if let badge = episode.badge {
                Text(badge)
                    .font(.system(size: 15 * metrics.scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 170 * metrics.scale, height: 126 * metrics.scale, alignment: .leading)
        .padding(18 * metrics.scale)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 20 * metrics.scale)
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

private struct BilibiliPosterImage: View {
    let url: URL?
    let title: String
    let width: Double
    let height: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.08))
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        artworkFallback
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
            } else {
                artworkFallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var artworkFallback: some View {
        Text(String(title.prefix(1)))
            .font(.system(size: 54, weight: .heavy))
            .foregroundStyle(.white.opacity(0.72))
    }
}

private struct BilibiliPlayerSurface: NSViewRepresentable {
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
