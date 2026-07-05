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
            VideoPlayer(player: controller.player)
                .ignoresSafeArea()
                .onAppear {
                    controller.load(app)
                }
                .onDisappear {
                    controller.stop()
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(app.name)
                    .font(.system(size: 42, weight: .bold))
                Text("Play/Pause toggles playback. Left/Right seek. Home returns.")
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

@MainActor
final class MediaRuntimeController: ObservableObject {
    let player = AVPlayer()
    private nonisolated(unsafe) var observer: NSObjectProtocol?
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
    }

    func load(_ app: TVAppProfile) {
        guard case let .media(url) = app.target else {
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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

        if state.isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }
}
