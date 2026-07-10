import AVFoundation
import AVKit
import SwiftUI

public struct MediaRuntimeView: View {
    public let app: TVAppProfile
    @StateObject private var controller = MediaRuntimeController()

    public init(app: TVAppProfile) {
        self.app = app
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaPlayerSurface(player: controller.player)
                .ignoresSafeArea()
                .onAppear {
                    controller.load(app)
                    setStatusClockHidden(true)
                }
                .onDisappear {
                    controller.stop()
                    setStatusClockHidden(false)
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(app.name)
                    .font(.system(size: 42, weight: .bold))
                Text(controller.statusText)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(30)
            .liquidGlassCard(isFocused: true, cornerRadius: 22)
            .padding(56)
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
final class MediaRuntimeController: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var statusText = "正在載入影片..."
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private nonisolated(unsafe) var itemObserver: NSKeyValueObservation?
    private var state = MediaControlState()

    init() {
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
        itemObserver?.invalidate()
    }

    func load(_ app: TVAppProfile) {
        guard case let .media(url) = app.target else {
            statusText = "這個 App 沒有可播放的影片。"
            return
        }

        statusText = "正在載入影片..."
        let item = AVPlayerItem(url: url)
        itemObserver?.invalidate()
        itemObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.statusText = "播放/暫停控制播放，左右快轉倒退，Home 返回。"
                case .failed:
                    self?.statusText = item.error?.localizedDescription ?? "影片載入失敗。"
                case .unknown:
                    self?.statusText = "正在載入影片..."
                @unknown default:
                    self?.statusText = "影片狀態已變更。"
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        state = MediaControlState(isPlaying: true)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func handle(_ command: RemoteCommand) {
        state.apply(command)

        if state.shouldExit {
            player.pause()
            return
        }

        if state.pendingSeekOffset != 0 {
            let current = player.currentTime().seconds
            let target = max(0, current + state.pendingSeekOffset)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }

        if state.shouldRestartFromBeginning {
            player.seek(to: .zero)
            player.play()
            return
        }

        if state.isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }
}

private struct MediaPlayerSurface: NSViewRepresentable {
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
