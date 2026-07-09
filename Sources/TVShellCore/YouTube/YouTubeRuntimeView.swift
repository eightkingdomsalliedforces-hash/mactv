import SwiftUI
import WebKit

public struct YouTubeRuntimeView: View {
    public let app: TVAppProfile
    @EnvironmentObject private var appState: AppState
    @StateObject private var controller = YouTubeRuntimeController()

    public init(app: TVAppProfile) {
        self.app = app
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.02, blue: 0.03),
                        Color(red: 0.14, green: 0.04, blue: 0.06),
                        Color(red: 0.03, green: 0.03, blue: 0.05)
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

                if controller.isKeyboardVisible {
                    VirtualKeyboardView(
                        title: "搜尋 YouTube",
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
                controller.updateGridColumns(videoGridColumns(for: metrics, size: proxy.size))
            }
            .onChange(of: proxy.size) { _, newSize in
                controller.updateGridColumns(videoGridColumns(for: TVMetrics(size: newSize), size: newSize))
            }
        }
        .task {
            controller.updateCredentials(appState.youtubeCredentials)
            controller.updateWatchHistory(appState.watchingHistory)
            await controller.load()
        }
        .onChange(of: appState.youtubeCredentials) { _, credentials in
            controller.updateCredentials(credentials)
            Task { await controller.load() }
        }
        .onChange(of: appState.watchingHistory) { _, history in
            controller.updateWatchHistory(history)
        }
    }

    private func videoGridColumns(for metrics: TVMetrics, size: CGSize) -> Int {
        Self.adaptiveColumns(
            availableWidth: size.width - (metrics.horizontalPadding * 2),
            minimumWidth: 408 * metrics.scale,
            spacing: 24 * metrics.scale
        )
    }

    private static func adaptiveColumns(availableWidth: Double, minimumWidth: Double, spacing: Double) -> Int {
        max(1, Int((max(availableWidth, minimumWidth) + spacing) / (minimumWidth + spacing)))
    }

    private func browser(metrics: TVMetrics) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 32 * metrics.scale) {
                    VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                        Text(app.name)
                            .font(.system(size: 76 * metrics.scale, weight: .bold))
                        Text(controller.statusText)
                            .font(.system(size: 28 * metrics.scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 408 * metrics.scale), spacing: 28 * metrics.scale)],
                        alignment: .leading,
                        spacing: 30 * metrics.scale
                    ) {
                        ForEach(Array(controller.videos.enumerated()), id: \.element.id) { index, video in
                            YouTubeVideoCard(
                                video: video,
                                isFocused: index == controller.state.focusedIndex,
                                metrics: metrics
                            )
                            .id("youtube-video-\(index)")
                        }
                    }

                    Text("方向鍵選影片，OK 播放，Menu 搜尋，Back 或 Home 返回。設定 TVSHELL_YOUTUBE_API_KEY 後會使用 YouTube Data API。")
                        .font(.system(size: 24 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
                .padding(.bottom, 54 * metrics.scale)
            }
            .scrollIndicators(.hidden)
            .onChange(of: controller.state.focusedIndex) { _, index in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("youtube-video-\(index)", anchor: .center)
                }
            }
            .onChange(of: controller.videos.count) { _, _ in
                withAnimation(TVMotion.focus) {
                    scrollProxy.scrollTo("youtube-video-\(controller.state.focusedIndex)", anchor: .center)
                }
            }
        }
    }


    private func player(metrics: TVMetrics) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let video = controller.focusedVideo {
                YouTubePlayerView(
                    videoID: video.id,
                    startSeconds: controller.resumeTime(for: video),
                    restartOnSelect: controller.canRestartFromBeginningWithSelect,
                    onPlaybackTime: { time, isPlaying in
                        controller.recordPlaybackTime(time, isPlaying: isPlaying)
                    }
                )
                    .ignoresSafeArea()
            }

            if controller.isPlayerHUDVisible {
                VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                    Text(controller.focusedVideo?.title ?? "YouTube")
                        .font(.system(size: 38 * metrics.scale, weight: .bold))
                        .lineLimit(2)
                    Text("播放/暫停控制播放，HUD 顯示時 OK 從 0:00 重播，HUD 消失後 OK 播放暫停。")
                        .font(.system(size: 22 * metrics.scale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(28 * metrics.scale)
                .liquidGlassCard(isFocused: true, cornerRadius: 22 * metrics.scale)
                .padding(50 * metrics.scale)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            MacTVYouTubeControls(metrics: metrics)
                .padding(.horizontal, 50 * metrics.scale)
                .padding(.bottom, 38 * metrics.scale)
        }
        .background(.black)
    }
}

@MainActor
final class YouTubeRuntimeController: ObservableObject {
    @Published private(set) var state = YouTubeRuntimeState(itemCount: 0)
    @Published private(set) var videos: [YouTubeVideo] = []
    @Published private(set) var statusText = "正在載入 YouTube..."
    @Published private(set) var isKeyboardVisible = false
    @Published private(set) var isPlayerHUDVisible = false
    @Published private(set) var canRestartFromBeginningWithSelect = false
    @Published private(set) var keyboardState = VirtualKeyboardState(text: "anime", layout: .zhuyin)
    private var gridColumns = 3
    private var currentQuery = "anime"
    private var watchHistory: [WatchHistoryEntry] = []
    private var lastRecordedVideoID: String?
    private var lastRecordedTime: Double = -1
    private var hidePlayerHUDTask: Task<Void, Never>?

    private var provider: any YouTubeVideoProvider
    private var credentials: YouTubeCredentials = .environment()
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init(provider: any YouTubeVideoProvider = YouTubeProviderFactory.defaultProvider()) {
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

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        hidePlayerHUDTask?.cancel()
    }

    var focusedVideo: YouTubeVideo? {
        guard videos.indices.contains(state.focusedIndex) else {
            return nil
        }
        return videos[state.focusedIndex]
    }

    func updateGridColumns(_ columns: Int) {
        gridColumns = max(1, columns)
    }

    func updateWatchHistory(_ history: [WatchHistoryEntry]) {
        watchHistory = history
    }

    func updateCredentials(_ credentials: YouTubeCredentials) {
        guard self.credentials != credentials else {
            return
        }
        self.credentials = credentials
        provider = YouTubeProviderFactory.defaultProvider(credentials: credentials)
    }

    func resumeTime(for video: YouTubeVideo) -> Double {
        watchHistory.first { $0.mediaID == watchMediaID(for: video) }?.resumeTimeSeconds ?? 0
    }

    func load() async {
        await load(query: currentQuery)
    }

    private func load(query: String) async {
        do {
            currentQuery = query
            keyboardState = VirtualKeyboardState(text: query, layout: .zhuyin)
            videos = try await provider.search(query: query)
            state.updateItemCount(videos.count)
            if videos.isEmpty {
                statusText = "來源：\(provider.displayName) · 找不到：\(query)"
            } else {
                statusText = "來源：\(provider.displayName) · 搜尋：\(query) · 已載入 \(videos.count) 部影片"
            }
        } catch {
            videos = []
            state.updateItemCount(videos.count)
            statusText = "YouTube 找不到可播放結果或 API 載入失敗：\(error.localizedDescription)"
        }
    }

    private func handle(_ command: RemoteCommand) {
        if isKeyboardVisible {
            handleKeyboard(command)
            return
        }

        if state.phase == .browsing, command == .menu {
            keyboardState = VirtualKeyboardState(text: currentQuery, layout: .zhuyin)
            isKeyboardVisible = true
            statusText = "YouTube 搜尋"
            return
        }

        let previousPhase = state.phase
        state.apply(command, columns: gridColumns)

        if previousPhase == .browsing, state.phase == .playing, let focusedVideo {
            showPlayerHUD(allowRestart: true)
            NotificationCenter.default.post(
                name: .tvShellRecordWatch,
                object: nil,
                userInfo: [
                    WatchHistoryNotification.entryKey: WatchHistoryEntry(
                        title: focusedVideo.title,
                        subtitle: focusedVideo.channelTitle,
                        kind: .youtube,
                        mediaID: watchMediaID(for: focusedVideo),
                        resumeTimeSeconds: resumeTime(for: focusedVideo)
                    )
                ]
            )
        }

        if previousPhase == .browsing, command == .back {
            NotificationCenter.default.post(name: .tvShellRequestLauncher, object: nil)
            return
        }

        if previousPhase == .playing, state.phase == .browsing {
            hidePlayerHUDTask?.cancel()
            isPlayerHUDVisible = false
            canRestartFromBeginningWithSelect = false
            return
        }

        if state.phase == .playing && (command == .playPause || command == .select) {
            showPlayerHUD(allowRestart: false)
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
            Task { await load(query: query) }
        case .cancelled:
            isKeyboardVisible = false
            statusText = "已關閉搜尋"
        }
    }

    func recordPlaybackTime(_ time: Double, isPlaying: Bool) {
        guard isPlaying,
              time.isFinite,
              let video = focusedVideo
        else {
            return
        }
        guard video.id != lastRecordedVideoID || abs(time - lastRecordedTime) >= 5 else {
            return
        }
        lastRecordedVideoID = video.id
        lastRecordedTime = time
        NotificationCenter.default.post(
            name: .tvShellRecordWatch,
            object: nil,
            userInfo: [
                WatchHistoryNotification.entryKey: WatchHistoryEntry(
                    title: video.title,
                    subtitle: video.channelTitle,
                    kind: .youtube,
                    mediaID: watchMediaID(for: video),
                    resumeTimeSeconds: max(0, time)
                )
            ]
        )
    }

    private func watchMediaID(for video: YouTubeVideo) -> String {
        "youtube:\(video.id)"
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
}

private struct YouTubeVideoCard: View {
    let video: YouTubeVideo
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        let cardWidth = 360 * metrics.scale
        let thumbnailHeight = 202 * metrics.scale

        VStack(alignment: .leading, spacing: 16 * metrics.scale) {
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .frame(width: cardWidth, height: thumbnailHeight)
                if let thumbnailURL = video.thumbnailURL {
                    AsyncImage(url: thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                            .controlSize(.large)
                    }
                    .frame(width: cardWidth, height: thumbnailHeight)
                    .clipped()
                } else {
                    Text("▶")
                        .font(.system(size: 56 * metrics.scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            .frame(width: cardWidth, height: thumbnailHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22 * metrics.scale, style: .continuous))

            Text(video.title)
                .font(.system(size: 28 * metrics.scale, weight: .bold))
                .lineLimit(2)
                .frame(minHeight: 68 * metrics.scale, alignment: .topLeading)

            Text(video.channelTitle)
                .font(.system(size: 22 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(22 * metrics.scale)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 26 * metrics.scale)
        .scaleEffect(isFocused ? 1.025 : 1)
        .animation(TVMotion.focus, value: isFocused)
    }
}

private struct MacTVYouTubeControls: View {
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 18 * metrics.scale) {
            Text("◀︎ 10")
            Text("播放 / 暫停")
            Text("10 ▶︎")
            Spacer()
            Text("遙控器：HUD 顯示時 OK 回 0:00，之後 OK 播放暫停")
        }
        .font(.system(size: 23 * metrics.scale, weight: .bold))
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 26 * metrics.scale)
        .padding(.vertical, 18 * metrics.scale)
        .liquidGlassCard(isFocused: false, cornerRadius: 24 * metrics.scale)
    }
}

struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String
    var startSeconds: Double = 0
    var restartOnSelect = false
    var onPlaybackTime: (@MainActor (Double, Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onPlaybackTime: onPlaybackTime)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.videoID = videoID
        context.coordinator.startSeconds = startSeconds
        context.coordinator.restartOnSelect = restartOnSelect
        context.coordinator.attach(to: webView)
        let page = YouTubeEmbedPage(videoID: videoID, startSeconds: startSeconds)
        webView.loadHTMLString(page.html, baseURL: page.baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPlaybackTime = onPlaybackTime
        context.coordinator.restartOnSelect = restartOnSelect
        let startChanged = abs(context.coordinator.startSeconds - startSeconds) > 0.5
        if context.coordinator.videoID != videoID || startChanged {
            context.coordinator.videoID = videoID
            context.coordinator.startSeconds = startSeconds
            let page = YouTubeEmbedPage(videoID: videoID, startSeconds: startSeconds)
            webView.loadHTMLString(page.html, baseURL: page.baseURL)
        }
    }

    @MainActor
    final class Coordinator {
        var videoID: String = ""
        var startSeconds: Double = 0
        var restartOnSelect = false
        var onPlaybackTime: (@MainActor (Double, Bool) -> Void)?
        private weak var webView: WKWebView?
        private nonisolated(unsafe) var observer: NSObjectProtocol?
        private nonisolated(unsafe) var telemetryTimer: Timer?

        init(onPlaybackTime: (@MainActor (Double, Bool) -> Void)?) {
            self.onPlaybackTime = onPlaybackTime
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            telemetryTimer?.invalidate()
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            startTelemetryTimerIfNeeded()
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: .tvShellRuntimeCommand,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else {
                        return
                    }
                    Task { @MainActor [weak self] in
                        self?.send(command)
                    }
                }
            }
        }

        private func send(_ command: RemoteCommand) {
            let jsCommand: String
            switch command {
            case .select:
                if restartOnSelect {
                    restartOnSelect = false
                    jsCommand = "restart"
                } else {
                    jsCommand = "playPause"
                }
            case .playPause:
                jsCommand = "playPause"
            case .left, .rewind:
                jsCommand = "seekBack"
            case .right, .fastForward:
                jsCommand = "seekForward"
            default:
                return
            }
            webView?.evaluateJavaScript("window.tvShellYouTubeCommand && window.tvShellYouTubeCommand('\(jsCommand)')") { _, _ in }
        }

        private func startTelemetryTimerIfNeeded() {
            guard telemetryTimer == nil else {
                return
            }
            telemetryTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollPlaybackState()
                }
            }
        }

        private func pollPlaybackState() {
            guard onPlaybackTime != nil else {
                return
            }
            webView?.evaluateJavaScript("window.tvShellYouTubeState && window.tvShellYouTubeState()") { [weak self] result, _ in
                guard let self,
                      let state = result as? [String: Any],
                      let currentTime = state["currentTime"] as? Double
                else {
                    return
                }
                let isPlaying = state["isPlaying"] as? Bool ?? false
                Task { @MainActor in
                    self.onPlaybackTime?(currentTime, isPlaying)
                }
            }
        }
    }

}
