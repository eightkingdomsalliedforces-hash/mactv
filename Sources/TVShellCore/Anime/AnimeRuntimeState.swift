public enum AnimeRuntimePhase: String, Codable, Equatable, Sendable {
    case browsing
    case playing
}

public struct AnimeRuntimeState: Equatable, Sendable {
    public private(set) var focusedEpisodeIndex: Int
    public private(set) var phase: AnimeRuntimePhase
    public private(set) var isDanmakuVisible: Bool
    private var episodeCount: Int

    public init(
        episodeCount: Int,
        focusedEpisodeIndex: Int = 0,
        phase: AnimeRuntimePhase = .browsing,
        isDanmakuVisible: Bool = true
    ) {
        self.episodeCount = max(episodeCount, 0)
        self.focusedEpisodeIndex = min(max(focusedEpisodeIndex, 0), max(episodeCount - 1, 0))
        self.phase = phase
        self.isDanmakuVisible = isDanmakuVisible
    }

    public mutating func updateEpisodeCount(_ count: Int) {
        episodeCount = max(count, 0)
        focusedEpisodeIndex = min(focusedEpisodeIndex, max(episodeCount - 1, 0))
    }

    public mutating func apply(_ command: RemoteCommand) {
        switch phase {
        case .browsing:
            handleBrowsing(command)
        case .playing:
            handlePlaying(command)
        }
    }

    private mutating func handleBrowsing(_ command: RemoteCommand) {
        switch command {
        case .left, .up:
            focusedEpisodeIndex = max(0, focusedEpisodeIndex - 1)
        case .right, .down:
            focusedEpisodeIndex = min(max(episodeCount - 1, 0), focusedEpisodeIndex + 1)
        case .select:
            if episodeCount > 0 {
                phase = .playing
            }
        case .menu:
            isDanmakuVisible.toggle()
        default:
            break
        }
    }

    private mutating func handlePlaying(_ command: RemoteCommand) {
        switch command {
        case .back:
            phase = .browsing
        case .menu:
            isDanmakuVisible.toggle()
        default:
            break
        }
    }
}
