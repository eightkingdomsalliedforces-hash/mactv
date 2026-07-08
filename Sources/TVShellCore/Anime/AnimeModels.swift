import Foundation

public struct AnimeSearchQuery: Equatable, Sendable {
    public var keyword: String

    public init(keyword: String) {
        self.keyword = keyword
    }
}

public struct AnimeEpisodeIdentity: Codable, Equatable, Hashable, Sendable {
    public var providerID: String
    public var subjectID: String
    public var episodeID: String
    public var subjectAliases: [String]
    public var playbackURL: URL?

    private enum CodingKeys: String, CodingKey {
        case providerID
        case subjectID
        case episodeID
        case subjectAliases
        case playbackURL
    }

    public init(
        providerID: String,
        subjectID: String,
        episodeID: String,
        subjectAliases: [String] = [],
        playbackURL: URL? = nil
    ) {
        self.providerID = providerID
        self.subjectID = subjectID
        self.episodeID = episodeID
        self.subjectAliases = subjectAliases
        self.playbackURL = playbackURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        subjectID = try container.decode(String.self, forKey: .subjectID)
        episodeID = try container.decode(String.self, forKey: .episodeID)
        subjectAliases = try container.decodeIfPresent([String].self, forKey: .subjectAliases) ?? []
        playbackURL = try container.decodeIfPresent(URL.self, forKey: .playbackURL)
    }
}

public struct AnimeEpisode: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var number: Int
    public var identity: AnimeEpisodeIdentity

    public init(id: String, title: String, number: Int, identity: AnimeEpisodeIdentity) {
        self.id = id
        self.title = title
        self.number = number
        self.identity = identity
    }
}

public struct AnimeSearchResult: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var coverURL: URL?
    public var originalTitle: String?
    public var airDate: String?
    public var score: Double?
    public var rank: Int?
    public var episodeCount: Int?
    public var episodes: [AnimeEpisode]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        coverURL: URL? = nil,
        originalTitle: String? = nil,
        airDate: String? = nil,
        score: Double? = nil,
        rank: Int? = nil,
        episodeCount: Int? = nil,
        episodes: [AnimeEpisode]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.originalTitle = originalTitle
        self.airDate = airDate
        self.score = score
        self.rank = rank
        self.episodeCount = episodeCount
        self.episodes = episodes
    }

    public var summaryText: String {
        subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? subtitle! : "暫無簡介。"
    }

    public var detailLine: String? {
        var parts: [String] = []
        if let originalTitle, originalTitle != title {
            parts.append(originalTitle)
        }
        if let airDate, airDate.isEmpty == false {
            parts.append("首播 \(airDate)")
        }
        if let episodeCount {
            parts.append("\(episodeCount) 集")
        }
        if let score {
            parts.append(String(format: "Bangumi %.1f", score))
        }
        if let rank {
            parts.append("Rank #\(rank)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct AnimeStreamCandidate: Codable, Equatable, Sendable {
    public var url: URL
    public var quality: String
    public var priority: Int
    public var headers: [String: String]

    public init(url: URL, quality: String, priority: Int = 0, headers: [String: String] = [:]) {
        self.url = url
        self.quality = quality
        self.priority = priority
        self.headers = headers
    }
}

public enum DanmakuMode: String, Codable, Equatable, Sendable {
    case scroll
    case top
    case bottom
}

public struct DanmakuComment: Codable, Equatable, Sendable {
    public var time: Double
    public var text: String
    public var colorHex: String
    public var mode: DanmakuMode

    public init(time: Double, text: String, colorHex: String = "#FFFFFF", mode: DanmakuMode = .scroll) {
        self.time = time
        self.text = text
        self.colorHex = colorHex
        self.mode = mode
    }
}
