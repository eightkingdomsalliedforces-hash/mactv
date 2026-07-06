public enum AnimeRuntimePhase: String, Codable, Equatable, Sendable {
    case titles
    case episodes
    case playing
}

public struct AnimeRuntimeState: Equatable, Sendable {
    public private(set) var focusedTitleIndex: Int
    public private(set) var focusedEpisodeIndex: Int
    public private(set) var phase: AnimeRuntimePhase
    public private(set) var isDanmakuVisible: Bool
    private var titleCount: Int
    private var episodeCount: Int

    public init(
        titleCount: Int = 0,
        episodeCount: Int = 0,
        focusedTitleIndex: Int = 0,
        focusedEpisodeIndex: Int = 0,
        phase: AnimeRuntimePhase = .titles,
        isDanmakuVisible: Bool = true
    ) {
        self.titleCount = max(titleCount, 0)
        self.episodeCount = max(episodeCount, 0)
        self.focusedTitleIndex = min(max(focusedTitleIndex, 0), max(titleCount - 1, 0))
        self.focusedEpisodeIndex = min(max(focusedEpisodeIndex, 0), max(episodeCount - 1, 0))
        self.phase = phase
        self.isDanmakuVisible = isDanmakuVisible
    }

    public mutating func updateTitleCount(_ count: Int) {
        titleCount = max(count, 0)
        focusedTitleIndex = min(focusedTitleIndex, max(titleCount - 1, 0))
    }

    public mutating func updateEpisodeCount(_ count: Int) {
        episodeCount = max(count, 0)
        focusedEpisodeIndex = min(focusedEpisodeIndex, max(episodeCount - 1, 0))
    }

    public mutating func openEpisodes(episodeCount: Int) {
        updateEpisodeCount(episodeCount)
        focusedEpisodeIndex = 0
        if episodeCount > 0 {
            phase = .episodes
        }
    }

    public mutating func apply(_ command: RemoteCommand) {
        switch phase {
        case .titles:
            handleTitles(command)
        case .episodes:
            handleEpisodes(command)
        case .playing:
            handlePlaying(command)
        }
    }

    private mutating func handleTitles(_ command: RemoteCommand) {
        switch command {
        case .left, .up:
            focusedTitleIndex = max(0, focusedTitleIndex - 1)
        case .right, .down:
            focusedTitleIndex = min(max(titleCount - 1, 0), focusedTitleIndex + 1)
        case .select:
            if titleCount > 0 {
                phase = .episodes
            }
        default:
            break
        }
    }

    private mutating func handleEpisodes(_ command: RemoteCommand) {
        switch command {
        case .left, .up:
            focusedEpisodeIndex = max(0, focusedEpisodeIndex - 1)
        case .right, .down:
            focusedEpisodeIndex = min(max(episodeCount - 1, 0), focusedEpisodeIndex + 1)
        case .select:
            if episodeCount > 0 {
                phase = .playing
            }
        case .back:
            phase = .titles
        default:
            break
        }
    }

    private mutating func handlePlaying(_ command: RemoteCommand) {
        switch command {
        case .back:
            phase = .episodes
        case .menu:
            isDanmakuVisible.toggle()
        default:
            break
        }
    }
}
