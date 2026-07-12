import SwiftUI

public struct ControlCenterView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Spacer(minLength: proxy.size.width * 0.42)

                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("控制中心")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text(Self.dateFormatter.string(from: Date()))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Spacer()
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                        spacing: 14
                    ) {
                        ControlCenterTile(
                            item: .home,
                            icon: "house.fill",
                            title: "主畫面",
                            value: "TVShell"
                        )
                        ControlCenterTile(
                            item: .focusMode,
                            icon: appState.isFocusModeEnabled ? "moon.fill" : "moon",
                            title: "勿擾模式",
                            value: appState.isFocusModeEnabled ? "開啟" : "關閉",
                            isEnabled: appState.isFocusModeEnabled
                        )
                        ControlCenterTile(
                            item: .audio,
                            icon: appState.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            title: "音量",
                            value: appState.isAudioMuted ? "靜音" : "\(Int(appState.quickVolume * 100))%",
                            isEnabled: appState.isAudioMuted
                        )
                        ControlCenterTile(
                            item: .display,
                            icon: "rectangle.expand.vertical",
                            title: "顯示縮放",
                            value: appState.displayScale.label
                        )
                        ControlCenterTile(
                            item: .wallpaper,
                            icon: "photo.on.rectangle.angled",
                            title: "壁紙",
                            value: wallpaperTitle
                        )
                        ControlCenterTile(
                            item: .webZoom,
                            icon: "text.magnifyingglass",
                            title: "網頁放大",
                            value: "\(Int(appState.webZoom * 100))%"
                        )
                        ControlCenterTile(
                            item: .remote,
                            icon: "dot.radiowaves.left.and.right",
                            title: "網路遙控器",
                            value: appState.networkRemoteStatus.isRunning ? "已啟動" : "啟動",
                            isEnabled: appState.networkRemoteStatus.isRunning
                        )
                        ControlCenterTile(
                            item: .settings,
                            icon: "gearshape.fill",
                            title: "設定",
                            value: "更多選項"
                        )
                        ControlCenterTile(
                            item: .danmakuVisibility,
                            icon: appState.danmakuDisplaySettings.isVisible ? "text.bubble.fill" : "text.bubble",
                            title: "彈幕顯示",
                            value: appState.danmakuDisplaySettings.isVisible ? "顯示" : "隱藏",
                            isEnabled: appState.danmakuDisplaySettings.isVisible
                        )
                        ControlCenterTile(
                            item: .danmakuSize,
                            icon: "textformat.size",
                            title: "彈幕大小",
                            value: appState.danmakuDisplaySettings.sizeLabel
                        )
                        ControlCenterTile(
                            item: .danmakuSpeed,
                            icon: "speedometer",
                            title: "彈幕速度",
                            value: appState.danmakuDisplaySettings.speedLabel
                        )
                        ControlCenterTile(
                            item: .danmakuOpacity,
                            icon: "circle.lefthalf.filled",
                            title: "彈幕透明度",
                            value: appState.danmakuDisplaySettings.opacityLabel
                        )
                        ControlCenterTile(
                            item: .danmakuDensity,
                            icon: "line.3.horizontal.decrease",
                            title: "彈幕密度",
                            value: appState.danmakuDisplaySettings.densityLabel
                        )
                    }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: min(650, proxy.size.height * 0.72))
                    .onChange(of: appState.controlCenterFocus) { _, focus in
                        withAnimation(TVMotion.focus) {
                            scrollProxy.scrollTo(focus, anchor: .center)
                        }
                    }
                    }

                    Text("方向鍵移動，OK 調整，左右可調整音量，Menu 或 Back 關閉")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }
                .padding(28)
                .frame(width: min(560, max(420, proxy.size.width * 0.34)), alignment: .topLeading)
                .tvOS18Surface(role: .panel, cornerRadius: 24)
                .padding(.top, max(26, proxy.safeAreaInsets.top + 18))
                .padding(.trailing, max(26, proxy.safeAreaInsets.trailing + 24))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .background(Color.black.opacity(0.18).ignoresSafeArea())
    }

    private var wallpaperTitle: String {
        switch appState.wallpaperSource {
        case let .builtIn(preset):
            preset.title
        case .localFile:
            "本機圖片"
        case .remoteImage:
            "線上壁紙"
        case .bingDaily:
            "Bing 每日圖片"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M月d日 E HH:mm"
        return formatter
    }()
}

private struct ControlCenterTile: View {
    @EnvironmentObject private var appState: AppState
    let item: ControlCenterFocus
    let icon: String
    let title: String
    let value: String
    var isEnabled = false

    private var isFocused: Bool {
        appState.controlCenterFocus == item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .foregroundStyle(isFocused ? .black : .white.opacity(0.92))
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(18)
        .tvOS18Surface(role: .row, isFocused: isFocused, cornerRadius: 12)
        .animation(TVMotion.focus, value: isFocused)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            appState.controlCenterFocus = item
            appState.handle(.select)
        }
        .id(item)
    }
}
