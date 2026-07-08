import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 34 * metrics.scale) {
                        Text("設定")
                            .font(.system(size: 76 * metrics.scale, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        SettingsOptionRow(
                            title: "介面縮放",
                            value: appState.displayScale.label,
                            isFocused: appState.settingsFocus == .scale,
                            metrics: metrics
                        )
                        .id(SettingsFocus.scale)

                        SettingsOptionRow(
                            title: "壁紙",
                            value: wallpaperLabel,
                            isFocused: appState.settingsFocus == .wallpaper,
                            metrics: metrics
                        )
                        .id(SettingsFocus.wallpaper)

                        SettingsOptionRow(
                            title: "網頁放大",
                            value: "\(Int(appState.webZoom * 100))%",
                            isFocused: appState.settingsFocus == .webZoom,
                            metrics: metrics
                        )
                        .id(SettingsFocus.webZoom)

                        SettingsOptionRow(
                            title: "彈幕大小",
                            value: appState.danmakuDisplaySettings.sizeLabel,
                            isFocused: appState.settingsFocus == .danmakuSize,
                            metrics: metrics
                        )
                        .id(SettingsFocus.danmakuSize)

                        SettingsOptionRow(
                            title: "彈幕速度",
                            value: appState.danmakuDisplaySettings.speedLabel,
                            isFocused: appState.settingsFocus == .danmakuSpeed,
                            metrics: metrics
                        )
                        .id(SettingsFocus.danmakuSpeed)

                        SettingsOptionRow(
                            title: "彈幕透明度",
                            value: appState.danmakuDisplaySettings.opacityLabel,
                            isFocused: appState.settingsFocus == .danmakuOpacity,
                            metrics: metrics
                        )
                        .id(SettingsFocus.danmakuOpacity)

                        SettingsOptionRow(
                            title: "彈幕密度",
                            value: appState.danmakuDisplaySettings.densityLabel,
                            isFocused: appState.settingsFocus == .danmakuDensity,
                            metrics: metrics
                        )
                        .id(SettingsFocus.danmakuDensity)

                        SettingsOptionRow(
                            title: "影片位置",
                            value: appState.videoSourceLabel,
                            isFocused: appState.settingsFocus == .videoSource,
                            metrics: metrics
                        )
                        .id(SettingsFocus.videoSource)

                        Text("上下選擇設定，左右調整；在影片位置按 OK 選擇本機影片。Home 或返回鍵回主畫面。")
                            .font(.system(size: 28 * metrics.scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(3)
                            .minimumScaleFactor(0.72)

                        DanmakuServiceStatusView(isConfigured: appState.dandanplayCredentials.isConfigured, metrics: metrics)

                        YouTubeAPIStatusView(isConfigured: appState.youtubeCredentials.isConfigured, metrics: metrics)

                        PermissionStatusView()
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, max(34, metrics.topPadding))
                }
                .scrollIndicators(.hidden)
                .onChange(of: appState.settingsFocus) { _, focus in
                    withAnimation(TVMotion.focus) {
                        scrollProxy.scrollTo(focus, anchor: .center)
                    }
                }
                .onAppear {
                    scrollProxy.scrollTo(appState.settingsFocus, anchor: .center)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var wallpaperLabel: String {
        switch appState.wallpaperSource {
        case let .builtIn(preset):
            preset.title
        case .localFile:
            "本機圖片"
        case .remoteImage:
            "壁紙提供商"
        }
    }
}

private struct YouTubeAPIStatusView: View {
    let isConfigured: Bool
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 22 * metrics.scale) {
            Circle()
                .fill(isConfigured ? .green : .orange)
                .frame(width: 22 * metrics.scale, height: 22 * metrics.scale)

            VStack(alignment: .leading, spacing: 8) {
                Text("YouTube API")
                    .font(.system(size: 32 * metrics.scale, weight: .bold))
                Text(isConfigured ? "已配置 YouTube Data API，YouTube App 會解析真實影片列表。" : "尚未配置 YouTube Data API。可用環境變數 TVSHELL_YOUTUBE_API_KEY。")
                    .font(.system(size: 24 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(30 * metrics.scale)
        .liquidGlassCard(isFocused: isConfigured == false, cornerRadius: 18 * metrics.scale)
    }
}

private struct DanmakuServiceStatusView: View {
    let isConfigured: Bool
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 22 * metrics.scale) {
            Circle()
                .fill(isConfigured ? .green : .orange)
                .frame(width: 22 * metrics.scale, height: 22 * metrics.scale)

            VStack(alignment: .leading, spacing: 8) {
                Text("彈幕服務")
                    .font(.system(size: 32 * metrics.scale, weight: .bold))
                Text(isConfigured ? "Dandanplay 已配置，可以接入遠端彈幕。" : "尚未配置 Dandanplay。可用環境變數 TVSHELL_DANDANPLAY_APP_ID / TVSHELL_DANDANPLAY_APP_SECRET。")
                    .font(.system(size: 24 * metrics.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(30 * metrics.scale)
        .liquidGlassCard(isFocused: isConfigured == false, cornerRadius: 18 * metrics.scale)
    }
}

private struct SettingsOptionRow: View {
    let title: String
    let value: String
    let isFocused: Bool
    let metrics: TVMetrics

    var body: some View {
        HStack(spacing: 28 * metrics.scale) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 32 * metrics.scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.system(size: 58 * metrics.scale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
            }

            Spacer()

            Text("<  >")
                .font(.system(size: 42 * metrics.scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.horizontal, 34 * metrics.scale)
        .padding(.vertical, 26 * metrics.scale)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 26 * metrics.scale)
    }
}
