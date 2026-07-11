import SwiftUI

public struct LauncherView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            TVControlBackdrop()

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
            case let .bilibili(app):
                BilibiliRuntimeView(app: app)
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

            if appState.isControlCenterPresented {
                ControlCenterView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .zIndex(40)
            }

            if appState.isStatusClockHidden == false {
                TVStatusClockOverlay()
                    .zIndex(appState.isControlCenterPresented ? 20 : 30)
            }
        }
        .animation(TVMotion.runtime, value: appState.activeRuntime)
        .animation(TVMotion.runtime, value: appState.openingAppName)
        .animation(TVMotion.runtime, value: appState.isControlCenterPresented)
    }

    private var launcher: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)
            let dockMetrics = TVMetrics(size: proxy.size, interfaceScale: appState.displayScale.multiplier())

            ZStack(alignment: .bottom) {
                TVOS18WallpaperView(source: appState.wallpaperSource)

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                            Color.clear
                                .frame(height: 1)
                                .id("launcher-top")

                            Spacer(minLength: max(380 * metrics.scale, proxy.size.height * 0.48))

                            Text(focusedApp?.name ?? "MacTV")
                                .font(.system(size: 30 * metrics.scale, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.leading, 30 * metrics.scale)

                            TVOSAppDock(
                                apps: appState.apps.filter(\.isVisibleOnHome),
                                focusedAppID: appState.focusedAppID,
                                metrics: dockMetrics
                            )

                            if appState.watchingHistory.isEmpty == false {
                                WatchHistoryRowView(
                                    entries: appState.watchingHistory,
                                    focusedEntryID: appState.focusedWatchHistoryID,
                                    isFocused: appState.launcherFocus == .history,
                                    metrics: metrics
                                )
                                    .id("launcher-history")
                            }

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

                            Text("方向鍵移動，OK 開啟，長按 Menu 開啟快捷設定。")
                                .font(.system(size: metrics.hintSize, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .padding(.bottom, 42 * metrics.scale)
                        }
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.bottom, 60 * metrics.scale)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: appState.focusedWatchHistoryID) { _, id in
                        guard let id else {
                            return
                        }
                        withAnimation(TVMotion.focus) {
                            scrollProxy.scrollTo("launcher-history-entry-\(id.uuidString)", anchor: .center)
                        }
                    }
                    .onChange(of: appState.launcherFocus) { _, focus in
                        withAnimation(TVMotion.focus) {
                            switch focus {
                            case .apps:
                                scrollProxy.scrollTo("launcher-top", anchor: .top)
                            case .history:
                                scrollProxy.scrollTo("launcher-history", anchor: .center)
                            }
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

}

private struct TVOSAppDock: View {
    let apps: [TVAppProfile]
    let focusedAppID: UUID?
    let metrics: TVMetrics

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 24 * metrics.scale) {
                ForEach(apps) { app in
                    AppCardView(app: app, isFocused: app.id == focusedAppID, metrics: metrics)
                        .id("tvos-dock-app-\(app.id.uuidString)")
                }
            }
            .padding(.horizontal, 34 * metrics.scale)
            .padding(.top, 26 * metrics.scale)
            .padding(.bottom, 14 * metrics.scale)
        }
        .scrollIndicators(.hidden)
        .tvOS18Surface(role: .panel, cornerRadius: 28 * metrics.scale)
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

private struct WatchHistoryRowView: View {
    @EnvironmentObject private var appState: AppState
    let entries: [WatchHistoryEntry]
    let focusedEntryID: UUID?
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            HStack(spacing: 18 * metrics.scale) {
                Text("最近觀看")
                    .font(.system(size: metrics.rowTitleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Button {
                    appState.clearWatchingHistory()
                } label: {
                    Text("清除")
                        .font(.system(size: 22 * metrics.scale, weight: .bold))
                        .padding(.horizontal, 18 * metrics.scale)
                        .padding(.vertical, 10 * metrics.scale)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                Text(isFocused ? "OK 續播，Menu 刪除目前項目" : "可用方向鍵移到最近觀看")
                    .font(.system(size: 20 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 20 * metrics.scale) {
                    ForEach(entries.prefix(8)) { entry in
                        ZStack(alignment: .topTrailing) {
                            VStack(alignment: .leading, spacing: 10 * metrics.scale) {
                                Text(entry.title)
                                    .font(.system(size: 28 * metrics.scale, weight: .bold))
                                    .lineLimit(2)
                                Text(entry.progressSubtitle)
                                    .font(.system(size: 20 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(1)
                            }
                            .frame(width: 340 * metrics.scale, alignment: .leading)
                            .frame(minHeight: 116 * metrics.scale, alignment: .leading)
                            .padding(22 * metrics.scale)
                            .liquidGlassCard(isFocused: isFocused && entry.id == focusedEntryID, cornerRadius: 24 * metrics.scale)
                            .scaleEffect(isFocused && entry.id == focusedEntryID ? 1.045 : 1)

                            Button {
                                appState.deleteWatchHistory(entry)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 18 * metrics.scale, weight: .bold))
                                    .frame(width: 42 * metrics.scale, height: 42 * metrics.scale)
                                    .background(.black.opacity(0.36), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(10 * metrics.scale)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 24 * metrics.scale, style: .continuous))
                        .onTapGesture {
                            appState.openWatchHistory(entry)
                        }
                        .id("launcher-history-entry-\(entry.id.uuidString)")
                    }
                }
                .padding(.horizontal, 12 * metrics.scale)
                .padding(.vertical, 34 * metrics.scale)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct TVStatusClockOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: Date(), by: 30)) { timeline in
                Text(Self.formatter.string(from: timeline.date))
                    .font(.system(size: max(22, min(proxy.size.width, proxy.size.height) * 0.028), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, max(18, proxy.safeAreaInsets.top + 12))
                    .padding(.trailing, max(24, proxy.safeAreaInsets.trailing + 28))
            }
        }
        .allowsHitTesting(false)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M月d日 E HH:mm"
        return formatter
    }()
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
                .padding(.horizontal, 28 * metrics.scale)
                .padding(.vertical, 34 * metrics.scale)
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
