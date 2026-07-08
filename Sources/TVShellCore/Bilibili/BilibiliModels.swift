import Foundation

public struct BilibiliSeason: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var subtitle: String?
    public var coverURL: URL?
    public var badge: String?
    public var totalText: String?

    public init(
        id: Int,
        title: String,
        subtitle: String? = nil,
        coverURL: URL? = nil,
        badge: String? = nil,
        totalText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.badge = badge
        self.totalText = totalText
    }
}

public struct BilibiliEpisode: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var aid: Int?
    public var cid: Int?
    public var bvid: String?
    public var title: String
    public var longTitle: String
    public var coverURL: URL?
    public var badge: String?
    public var number: Int

    public init(
        id: Int,
        aid: Int? = nil,
        cid: Int? = nil,
        bvid: String? = nil,
        title: String,
        longTitle: String = "",
        coverURL: URL? = nil,
        badge: String? = nil,
        number: Int
    ) {
        self.id = id
        self.aid = aid
        self.cid = cid
        self.bvid = bvid
        self.title = title
        self.longTitle = longTitle
        self.coverURL = coverURL
        self.badge = badge
        self.number = number
    }
}

public struct BilibiliSeasonDetail: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var coverURL: URL?
    public var subtitle: String?
    public var evaluate: String?
    public var ratingScore: Double?
    public var views: Int?
    public var danmaku: Int?
    public var episodes: [BilibiliEpisode]

    public init(
        id: Int,
        title: String,
        coverURL: URL? = nil,
        subtitle: String? = nil,
        evaluate: String? = nil,
        ratingScore: Double? = nil,
        views: Int? = nil,
        danmaku: Int? = nil,
        episodes: [BilibiliEpisode]
    ) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.subtitle = subtitle
        self.evaluate = evaluate
        self.ratingScore = ratingScore
        self.views = views
        self.danmaku = danmaku
        self.episodes = episodes
    }
}

public struct BilibiliPlaybackStream: Equatable, Sendable {
    public var url: URL
    public var quality: String
    public var headers: [String: String]
    public var durationSeconds: Double?

    public init(url: URL, quality: String, headers: [String: String], durationSeconds: Double? = nil) {
        self.url = url
        self.quality = quality
        self.headers = headers
        self.durationSeconds = durationSeconds
    }
}

public enum BilibiliRuntimePhase: String, Codable, Equatable, Sendable {
    case browsing
    case detail
    case playing
}

public struct BilibiliRuntimeState: Equatable, Sendable {
    public private(set) var phase: BilibiliRuntimePhase
    public private(set) var focusedSeasonIndex: Int
    public private(set) var focusedEpisodeIndex: Int
    private var seasonCount: Int
    private var episodeCount: Int

    public init(
        phase: BilibiliRuntimePhase = .browsing,
        focusedSeasonIndex: Int = 0,
        focusedEpisodeIndex: Int = 0,
        seasonCount: Int = 0,
        episodeCount: Int = 0
    ) {
        self.phase = phase
        self.seasonCount = max(seasonCount, 0)
        self.episodeCount = max(episodeCount, 0)
        self.focusedSeasonIndex = min(max(focusedSeasonIndex, 0), max(seasonCount - 1, 0))
        self.focusedEpisodeIndex = min(max(focusedEpisodeIndex, 0), max(episodeCount - 1, 0))
    }

    public mutating func updateSeasonCount(_ count: Int) {
        seasonCount = max(count, 0)
        focusedSeasonIndex = min(focusedSeasonIndex, max(seasonCount - 1, 0))
    }

    public mutating func updateEpisodeCount(_ count: Int) {
        episodeCount = max(count, 0)
        focusedEpisodeIndex = min(focusedEpisodeIndex, max(episodeCount - 1, 0))
    }

    public mutating func resetToBrowsing() {
        phase = .browsing
    }

    public mutating func openDetail() {
        if seasonCount > 0 {
            phase = .detail
        }
    }

    public mutating func openPlayer() {
        if episodeCount > 0 {
            phase = .playing
        }
    }

    public mutating func closePlayer() {
        phase = .detail
    }

    public mutating func applyBrowsing(_ command: RemoteCommand, columns: Int) {
        let columnStep = max(columns, 1)
        switch command {
        case .left:
            focusedSeasonIndex = max(0, focusedSeasonIndex - 1)
        case .right:
            focusedSeasonIndex = min(max(seasonCount - 1, 0), focusedSeasonIndex + 1)
        case .up:
            focusedSeasonIndex = max(0, focusedSeasonIndex - columnStep)
        case .down:
            focusedSeasonIndex = min(max(seasonCount - 1, 0), focusedSeasonIndex + columnStep)
        default:
            break
        }
    }

    public mutating func applyDetail(_ command: RemoteCommand, columns: Int) {
        let columnStep = max(columns, 1)
        switch command {
        case .left:
            focusedEpisodeIndex = max(0, focusedEpisodeIndex - 1)
        case .right:
            focusedEpisodeIndex = min(max(episodeCount - 1, 0), focusedEpisodeIndex + 1)
        case .up:
            focusedEpisodeIndex = max(0, focusedEpisodeIndex - columnStep)
        case .down:
            focusedEpisodeIndex = min(max(episodeCount - 1, 0), focusedEpisodeIndex + columnStep)
        default:
            break
        }
    }
}
