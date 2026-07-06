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

    public init(providerID: String, subjectID: String, episodeID: String) {
        self.providerID = providerID
        self.subjectID = subjectID
        self.episodeID = episodeID
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
    public var episodes: [AnimeEpisode]

    public init(id: String, title: String, subtitle: String? = nil, coverURL: URL? = nil, episodes: [AnimeEpisode]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.episodes = episodes
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
