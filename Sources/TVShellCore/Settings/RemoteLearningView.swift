import SwiftUI

public struct RemoteLearningView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var mappingCenter = RemoteMappingCenter.shared
    @State private var focusedCommandIndex = 0
    private let learnableCommands: [RemoteCommand] = [
        .up, .down, .left, .right, .select, .back, .home, .menu,
        .playPause, .rewind, .fastForward, .volumeUp, .volumeDown, .mute
    ]

    public init() {}

    public var body: some View {
        ZStack {
            TVOS18Backdrop(accent: Color(red: 0.14, green: 0.18, blue: 0.20))

            GeometryReader { proxy in
                let metrics = TVMetrics(size: proxy.size)

                TVOS18SettingsSplitView(metrics: metrics) {
                    TVOS18SettingsSidebar(
                        symbolName: "dot.radiowaves.left.and.right",
                        title: "遙控器設定",
                        subtitle: "檢查按鍵辨識、網路遙控器與 macOS 輔助使用權限。",
                        metrics: metrics
                    )
                } content: {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                            TVOS18SettingsRow(
                                symbolName: "remote.fill",
                                title: "最近指令",
                                value: appState.lastCommand?.description ?? "等待輸入",
                                isFocused: false,
                                metrics: metrics
                            )

                            VStack(alignment: .leading, spacing: 12 * metrics.scale) {
                                Text("自定義按鍵")
                                    .font(.system(size: 30 * metrics.scale, weight: .bold))
                                Text(mappingCenter.statusText)
                                    .font(.system(size: 20 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(mappingCenter.captureTarget == nil ? .white.opacity(0.62) : .orange)

                                ForEach(Array(learnableCommands.enumerated()), id: \.offset) { index, command in
                                    TVOS18SettingsRow(
                                        symbolName: commandSymbol(command),
                                        title: commandTitle(command),
                                        value: mappingCenter.captureTarget == command ? "等待按鍵…" : "按 OK 學習",
                                        isFocused: index == focusedCommandIndex,
                                        metrics: metrics
                                    )
                                }

                                Text("最近原始輸入：\(mappingCenter.lastRawEventDescription) · 已學習 \(mappingCenter.learnedMappingCount) 個。Menu 清除全部。")
                                    .font(.system(size: 18 * metrics.scale, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.52))
                            }
                            .padding(22 * metrics.scale)
                            .tvOS18Surface(role: .panel, cornerRadius: 12 * metrics.scale)

                            VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                                Text("Android 藍牙備援")
                                    .font(.system(size: 28 * metrics.scale, weight: .semibold))
                                Text("同一 Wi-Fi 的 Android 手機瀏覽器可開啟：")
                                    .font(.system(size: 22 * metrics.scale, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.62))
                                Text(appState.networkRemoteStatus.urlText)
                                    .font(.system(size: 28 * metrics.scale, weight: .bold))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.58)
                                    .textSelection(.enabled)
                                Text(appState.networkRemoteStatus.message)
                                    .font(.system(size: 20 * metrics.scale, weight: .semibold))
                                    .foregroundStyle(appState.networkRemoteStatus.isRunning ? .green : .orange)
                            }
                            .padding(22 * metrics.scale)
                            .tvOS18Surface(role: .panel, cornerRadius: 12 * metrics.scale)

                            PermissionStatusView()
                        }
                        .padding(.horizontal, 10 * metrics.scale)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            appState.startNetworkRemoteServer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvShellRuntimeCommand)) { notification in
            guard let command = notification.userInfo?[RuntimeCommandNotification.commandKey] as? RemoteCommand else { return }
            switch command {
            case .up:
                focusedCommandIndex = max(0, focusedCommandIndex - 1)
            case .down:
                focusedCommandIndex = min(learnableCommands.count - 1, focusedCommandIndex + 1)
            case .select:
                mappingCenter.armCapture(for: learnableCommands[focusedCommandIndex])
            case .menu:
                mappingCenter.reset()
            default:
                break
            }
        }
    }

    private func commandTitle(_ command: RemoteCommand) -> String {
        switch command {
        case .up: "上"
        case .down: "下"
        case .left: "左"
        case .right: "右"
        case .select: "OK／選擇"
        case .back: "返回"
        case .home: "Home"
        case .menu: "Menu／控制中心"
        case .playPause: "播放／暫停"
        case .rewind: "倒退"
        case .fastForward: "快轉"
        case .volumeUp: "音量加"
        case .volumeDown: "音量減"
        case .mute: "靜音"
        case .longPress: "長按"
        }
    }

    private func commandSymbol(_ command: RemoteCommand) -> String {
        switch command {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .select: "circle.inset.filled"
        case .back: "arrow.uturn.backward"
        case .home: "house.fill"
        case .menu: "line.3.horizontal"
        case .playPause: "playpause.fill"
        case .rewind: "backward.fill"
        case .fastForward: "forward.fill"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .mute: "speaker.slash.fill"
        case .longPress: "hand.tap.fill"
        }
    }
}
