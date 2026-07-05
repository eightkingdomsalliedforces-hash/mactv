import AVFoundation
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
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.04, blue: 0.08),
                        Color(red: 0.08, green: 0.10, blue: 0.16),
                        Color(red: 0.16, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                switch controller.state.phase {
                case .browsing:
                    browser(metrics: metrics)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .playing:
                    player(metrics: metrics)
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .animation(TVMotion.runtime, value: controller.state.phase)
            .foregroundStyle(.white)
        }
        .task {
            await controller.load(
                sourceProvider: AnimeSourceProviderFactory.provider(
                    catalog: appState.animeSourceCatalog,
                    youtubeCredentials: appState.youtubeCredentials
                )
            )
        }
        .onDisappear {
            controller.stop()
        }
    }

    private func browser(metrics: TVMetrics) -> some View {
        VStack(alignment: .leading, spacing: 34 * metrics.scale) {
            VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                Text(app.name)
                    .font(.system(size: 76 * metrics.scale, weight: .bold))
                Text(controller.statusText)
                    .font(.system(size: 28 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }

            if let title = controller.currentTitle {
                VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                    Text(title.title)
                        .font(.system(size: 42 * metrics.scale, weight: .bold))
                    Text(title.subtitle ?? "示範來源")
                        .font(.system(size: 25 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 230 * metrics.scale), spacing: 22 * metrics.scale)],
                alignment: .leading,
                spacing: 22 * metrics.scale
            ) {
                ForEach(Array(controller.episodes.enumerated()), id: \.element.id) { index, episode in
                    EpisodeCard(
                        episode: episode,
                        isFocused: index == controller.state.focusedEpisodeIndex,
                        metrics: metrics
                    )
                }
            }

            Spacer()

            Text("方向鍵選集，OK 播放，Menu 換搜尋，Home 回主畫面。播放中 Menu 開關彈幕。")
                .font(.system(size: 25 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, 54 * metrics.scale)
    }

    private func player(metrics: TVMetrics) -> some View {
        ZStack(alignment: .bottomLeading) {
            if controller.state.isDanmakuVisible {
                DanmakuOverlay(comments: controller.visibleDanmaku, metrics: metrics)
                    .transition(.opacity)
            }

            if let youtubeVideoID = controller.currentYouTubeVideoID {
                YouTubePlayerView(videoID: youtubeVideoID)
                    .ignoresSafeArea()
            } else {
                AnimePlayerSurface(player: controller.player)
                    .ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                Text(controller.playingTitle)
                    .font(.system(size: 38 * metrics.scale, weight: .bold))
                Text("播放/暫停控制播放，左右快轉倒退，Back 回選集，Menu 彈幕。")
                    .font(.system(size: 22 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(28 * metrics.scale)
            .liquidGlassCard(isFocused: true, cornerRadius: 22 * metrics.scale)
            .padding(50 * metrics.scale)
        }
        .background(.black)
    }
}

@MainActor
final class AnimeRuntimeController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var state = AnimeRuntimeState(episodeCount: 0)
    @Published private(set) var currentTitle: AnimeSearchResult?
    @Published private(set) var episodes: [AnimeEpisode] = []
    @Published private(set) var statusText = "正在載入動畫源..."
    @Published private(set) var visibleDanmaku: [DanmakuComment] = []
    @Published private(set) var currentYouTubeVideoID: String?

    private var sourceProvider: (any AnimeSourceProvider)?
    private let danmakuProvider: any DanmakuProvider
    private let searchKeywords = ["芙莉蓮", "藥師少女", "我推的孩子", "咒術迴戰", "孤獨搖滾"]
    private var searchKeywordIndex = 0
    private var comments: [DanmakuComment] = []
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private nonisolated(unsafe) var timeObserver: Any?
    private nonisolated(unsafe) var itemObserver: NSKeyValueObservation?
    private var mediaState = MediaControlState()

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
        itemObserver?.invalidate()
    }

    var playingTitle: String {
        guard episodes.indices.contains(state.focusedEpisodeIndex) else {
            return currentTitle?.title ?? "動畫"
        }
        return "\(currentTitle?.title ?? "動畫") · \(episodes[state.focusedEpisodeIndex].title)"
    }

    func load(sourceProvider provider: (any AnimeSourceProvider)? = nil) async {
        if let provider {
            sourceProvider = provider
        }

        guard let sourceProvider else {
            statusText = "沒有可用動畫來源。請先到動漫來源頁啟用來源。"
            return
        }

        do {
            let keyword = searchKeywords[searchKeywordIndex]
            let results = try await sourceProvider.search(AnimeSearchQuery(keyword: keyword))
            guard let first = results.first else {
                statusText = "沒有找到動畫。"
                return
            }

            currentTitle = first
            episodes = try await sourceProvider.episodes(for: first)
            state.updateEpisodeCount(episodes.count)
            statusText = "來源：\(sourceProvider.displayName) · 已載入 \(episodes.count) 集 · 搜尋：\(keyword)"
        } catch {
            statusText = "動畫源載入失敗：\(error.localizedDescription)"
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentYouTubeVideoID = nil
    }

    private func handle(_ command: RemoteCommand) {
        if state.phase == .browsing, command == .menu {
            searchKeywordIndex = (searchKeywordIndex + 1) % searchKeywords.count
            episodes = []
            currentTitle = nil
            state = AnimeRuntimeState(episodeCount: 0)
            statusText = "正在搜尋：\(searchKeywords[searchKeywordIndex])..."
            Task { await load() }
            return
        }

        let previousPhase = state.phase
        state.apply(command)

        if previousPhase == .browsing, command == .back {
            NotificationCenter.default.post(name: .tvShellRequestLauncher, object: nil)
            return
        }

        if previousPhase == .browsing, state.phase == .playing {
            Task { await playFocusedEpisode() }
            return
        }

        if previousPhase == .playing, state.phase == .browsing {
            stop()
            statusText = "已回到選集。"
            return
        }

        if state.phase == .playing {
            handlePlayback(command)
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
                phase: .browsing,
                isDanmakuVisible: state.isDanmakuVisible
            )
            return
        }

        do {
            statusText = "正在解析 \(episode.title)..."
            let candidates = try await sourceProvider.streams(for: episode)
            guard let stream = AnimeStreamSelector.bestCandidate(from: candidates) else {
                statusText = "沒有可用播放源。"
                state = AnimeRuntimeState(
                    episodeCount: episodes.count,
                    focusedEpisodeIndex: state.focusedEpisodeIndex,
                    phase: .browsing,
                    isDanmakuVisible: state.isDanmakuVisible
                )
                return
            }

            comments = DanmakuAggregator.merge([try await danmakuProvider.comments(for: episode.identity)])
            loadPlayer(stream)
            statusText = "播放源：\(stream.quality) · 彈幕 \(comments.count) 條"
        } catch {
            if error as? YouTubeAPIError == .missingAPIKey {
                statusText = "需要設定 TVSHELL_YOUTUBE_API_KEY 才能搜尋並播放 YouTube 動漫來源。"
            } else {
                statusText = "解析失敗：\(error.localizedDescription)"
            }
            state = AnimeRuntimeState(
                episodeCount: episodes.count,
                focusedEpisodeIndex: state.focusedEpisodeIndex,
                phase: .browsing,
                isDanmakuVisible: state.isDanmakuVisible
            )
        }
    }

    private func loadPlayer(_ stream: AnimeStreamCandidate) {
        if stream.url.scheme == "youtube" {
            currentYouTubeVideoID = stream.url.host ?? stream.url.absoluteString.replacingOccurrences(of: "youtube://", with: "")
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        currentYouTubeVideoID = nil
        let item = AVPlayerItem(url: stream.url)
        itemObserver?.invalidate()
        itemObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                if case .failed = item.status {
                    self?.statusText = item.error?.localizedDescription ?? "動畫播放失敗。"
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        mediaState = MediaControlState(isPlaying: true)
        installTimeObserverIfNeeded()
    }

    private func handlePlayback(_ command: RemoteCommand) {
        mediaState.apply(command)

        if mediaState.pendingSeekOffset != 0 {
            let current = player.currentTime().seconds
            let target = max(0, current + mediaState.pendingSeekOffset)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }

        if command == .playPause || command == .select {
            if mediaState.isPlaying {
                player.play()
            } else {
                player.pause()
            }
        }
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else {
            return
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateDanmaku(time: time.seconds)
            }
        }
    }

    private func updateDanmaku(time: Double) {
        visibleDanmaku = comments
            .filter { abs($0.time - time) < 2.2 }
            .suffix(5)
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

private struct DanmakuOverlay: View {
    let comments: [DanmakuComment]
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            ForEach(Array(comments.enumerated()), id: \.offset) { index, comment in
                Text(verbatim: comment.text)
                    .modifier(DanmakuTextStyle(metrics: metrics))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.92), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 20 * metrics.scale)
                    .padding(.vertical, 8 * metrics.scale)
                    .background(.black.opacity(0.22), in: Capsule())
                    .offset(x: CGFloat(index) * CGFloat(34 * metrics.scale))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 78 * metrics.scale)
        .padding(.leading, 78 * metrics.scale)
        .animation(TVMotion.focus, value: comments)
    }
}

private struct DanmakuTextStyle: ViewModifier {
    let metrics: TVMetrics

    func body(content: Content) -> some View {
        content.font(.system(size: 31 * metrics.scale, weight: .bold))
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
