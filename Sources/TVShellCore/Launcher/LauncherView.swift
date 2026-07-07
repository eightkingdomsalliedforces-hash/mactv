import SwiftUI

public struct LauncherView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.12, blue: 0.18),
                    Color(red: 0.15, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch appState.activeRuntime {
            case .launcher:
                launcher
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case let .web(app):
                WebAppRuntimeView(app: app, webZoom: appState.webZoom, webRemoteMode: appState.webRemoteMode)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            case let .media(app):
                MediaRuntimeView(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            case let .anime(app):
                AnimeRuntimeView(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            case let .youtube(app):
                YouTubeRuntimeView(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            case let .native(app):
                NativeRuntimeInterimView(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            case .remoteLearning:
                RemoteLearningView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .settings:
                SettingsView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .appManagement:
                AppManagementView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            case .animeSourceManagement:
                AnimeSourceManagementView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let openingAppName = appState.openingAppName {
                OpeningAppOverlay(appName: openingAppName)
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(10)
            }
        }
        .animation(TVMotion.runtime, value: appState.activeRuntime)
        .animation(TVMotion.runtime, value: appState.openingAppName)
    }

    private var launcher: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ZStack(alignment: .topLeading) {
                heroBackground

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 42 * metrics.scale) {
                            topBar(metrics: metrics)
                                .padding(.top, metrics.topPadding)

                            VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                                Text(focusedApp?.name ?? "TV Shell")
                                    .font(.system(size: metrics.heroTitleSize, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text(heroSubtitle)
                                    .font(.system(size: metrics.heroSubtitleSize, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.76)
                            }
                            .padding(.top, 16 * metrics.scale)

                            quickActionBar(metrics: metrics)

                            if appState.watchingHistory.isEmpty == false {
                                WatchHistoryRowView(entries: appState.watchingHistory, metrics: metrics)
                                    .id("launcher-history")
                            }

                            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                                ForEach(LauncherLayout.sections(for: appState.apps)) { section in
                                    LauncherRowView(section: section, focusedAppID: appState.focusedAppID, metrics: metrics)
                                        .id("launcher-section-\(section.id)")
                                }
                            }
                            .scaleEffect(appState.displayScale.multiplier(), anchor: .topLeading)

                            if let statusMessage = appState.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 24 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.74)
                                    .padding(.horizontal, 24 * metrics.scale)
                                    .padding(.vertical, 16 * metrics.scale)
                                    .liquidGlassCard(isFocused: true, cornerRadius: 20)
                            }

                            Text("方向鍵移動，OK 開啟，返回或 Home 回主畫面。")
                                .font(.system(size: metrics.hintSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .padding(.bottom, 42 * metrics.scale)
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        .padding(.horizontal, metrics.horizontalPadding)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: appState.focusedAppID) { _, id in
                        guard let sectionID = focusedSectionID(for: id) else {
                            return
                        }
                        withAnimation(TVMotion.focus) {
                            scrollProxy.scrollTo("launcher-section-\(sectionID)", anchor: .center)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var focusedApp: TVAppProfile? {
        appState.apps.first { $0.id == appState.focusedAppID }
    }

    private func focusedSectionID(for appID: UUID?) -> String? {
        guard let appID else {
            return nil
        }
        return LauncherLayout.sections(for: appState.apps)
            .first { section in section.apps.contains { $0.id == appID } }?
            .id
    }

    private var heroSubtitle: String {
        guard let app = focusedApp else {
            return "適合大螢幕與遙控器的 macOS 主畫面"
        }

        switch app.target {
        case .youtube:
            return "原生大螢幕 YouTube，使用 Data API 解析影片列表"
        case .anime:
            return "自動解析動畫源、選集播放，並顯示 Bangumi 風格彈幕"
        case .media:
            return "用大螢幕控制列播放本機或串流影片"
        case .nativeApp:
            return "開啟並用輔助使用控制原生 macOS App"
        case let .web(url) where url.scheme == "tv-shell" && url.host == "anime-sources":
            return "管理 Animeko 風格來源、線路、狀態與驗證入口"
        case let .web(url) where url.scheme == "tv-shell":
            return "設定遙控器、縮放、壁紙與系統控制"
        case .web:
            return "以放大網頁與虛擬滑鼠模式瀏覽"
        }
    }

    private func topBar(metrics: TVMetrics) -> some View {
        HStack(spacing: 18) {
            Text("TV Shell")
                .font(.system(size: 28 * metrics.scale, weight: .bold))
            Text(appState.displayScale.label)
                .font(.system(size: 24 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(commandLabel)
                .font(.system(size: 23 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 28 * metrics.scale)
        .padding(.vertical, 18 * metrics.scale)
        .liquidGlassCard(isFocused: false, cornerRadius: 26)
    }

    private func quickActionBar(metrics: TVMetrics) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16 * metrics.scale) {
                ForEach(LauncherLayout.quickActions(for: appState.apps)) { app in
                    Button {
                        appState.focusedAppID = app.id
                        appState.handle(.select)
                    } label: {
                        Text(app.name)
                            .font(.system(size: 23 * metrics.scale, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 22 * metrics.scale)
                            .padding(.vertical, 14 * metrics.scale)
                            .liquidGlassCard(isFocused: app.id == appState.focusedAppID, cornerRadius: 22)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8 * metrics.scale)
        }
        .scrollIndicators(.hidden)
    }

    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: heroColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [.white.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 780
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(TVMotion.hero, value: appState.focusedAppID)
        .animation(TVMotion.hero, value: appState.wallpaperSource)
    }

    private var heroColors: [Color] {
        switch appState.wallpaperSource {
        case let .builtIn(preset):
            return preset.palette.colors.map(Color.init(wallpaperColor:))
        case .localFile, .remoteImage:
            return WallpaperPreset.graphite.palette.colors.map(Color.init(wallpaperColor:))
        }
    }

    private var commandLabel: String {
        if case .web = appState.activeRuntime {
            return "網頁：\(appState.webRemoteMode.title)"
        }
        return appState.lastCommand.map { "最近：\($0.description)" } ?? "等待遙控器"
    }
}

private struct OpeningAppOverlay: View {
    let appName: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(String(appName.prefix(1)))
                    .font(.system(size: 78, weight: .bold, design: .rounded))
                    .frame(width: 152, height: 152)
                    .liquidGlassCard(isFocused: true, cornerRadius: 38)

                Text(appName)
                    .font(.system(size: 66, weight: .bold))

                Text("正在開啟")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 72)
            .padding(.vertical, 58)
            .liquidGlassCard(isFocused: true, cornerRadius: 34)
        }
    }
}

private extension Color {
    init(wallpaperColor: WallpaperColor) {
        self.init(red: wallpaperColor.red, green: wallpaperColor.green, blue: wallpaperColor.blue)
    }
}

private struct WatchHistoryRowView: View {
    let entries: [WatchHistoryEntry]
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            Text("最近觀看")
                .font(.system(size: metrics.rowTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            ScrollView(.horizontal) {
                HStack(spacing: 20 * metrics.scale) {
                    ForEach(entries.prefix(8)) { entry in
                        VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                            Text(entry.title)
                                .font(.system(size: 28 * metrics.scale, weight: .bold))
                                .lineLimit(2)
                            Text(entry.subtitle ?? entry.kind.rawValue)
                                .font(.system(size: 20 * metrics.scale, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1)
                        }
                        .frame(width: 340 * metrics.scale, alignment: .leading)
                        .frame(minHeight: 116 * metrics.scale, alignment: .leading)
                        .padding(22 * metrics.scale)
                        .liquidGlassCard(isFocused: false, cornerRadius: 24 * metrics.scale)
                    }
                }
                .padding(.horizontal, 8 * metrics.scale)
                .padding(.vertical, 10 * metrics.scale)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct LauncherRowView: View {
    let section: LauncherSection
    let focusedAppID: UUID?
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            Text(section.title)
                .font(.system(size: metrics.rowTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            ScrollView(.horizontal) {
                HStack(spacing: metrics.cardSpacing) {
                    ForEach(section.apps) { app in
                        AppCardView(title: app.name, isFocused: app.id == focusedAppID, metrics: metrics)
                    }
                }
                .padding(.horizontal, 22 * metrics.scale)
                .padding(.vertical, 20 * metrics.scale)
            }
            .scrollIndicators(.hidden)
        }
        .animation(TVMotion.focus, value: focusedAppID)
    }
}

private struct NativeRuntimeInterimView: View {
    let app: TVAppProfile

    var body: some View {
        VStack(spacing: 32) {
            Text(app.name)
                .font(.system(size: 72, weight: .bold))
            Text("原生 App 已開啟，按 Home 返回。")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("已啟用輔助使用控制基礎；按 Home 返回主畫面。")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .foregroundStyle(.white)
    }
}
