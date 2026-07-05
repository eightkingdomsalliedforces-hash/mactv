import Foundation

public protocol AnimeSourceProvider: Sendable {
    var id: String { get }
    var displayName: String { get }

    func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult]
    func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode]
    func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate]
}

public protocol DanmakuProvider: Sendable {
    func comments(for episode: AnimeEpisodeIdentity) async throws -> [DanmakuComment]
}

public struct StaticAnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id: String
    public let displayName: String
    public let resolverKind: AnimeResolverKind
    private let results: [AnimeSearchResult]
    private let streamCandidates: [String: [AnimeStreamCandidate]]

    public init(
        id: String,
        displayName: String,
        results: [AnimeSearchResult],
        streams: [String: [AnimeStreamCandidate]],
        resolverKind: AnimeResolverKind = .http
    ) {
        self.id = id
        self.displayName = displayName
        self.results = results
        self.streamCandidates = streams
        self.resolverKind = resolverKind
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let trimmedKeyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKeyword.isEmpty == false else {
            return results
        }

        return results.filter { result in
            result.title.localizedCaseInsensitiveContains(trimmedKeyword)
                || (result.subtitle?.localizedCaseInsensitiveContains(trimmedKeyword) ?? false)
        }
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes.sorted { $0.number < $1.number }
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        (streamCandidates[episode.id] ?? []).sorted { left, right in
            if left.priority == right.priority {
                return left.quality > right.quality
            }
            return left.priority > right.priority
        }
    }
}

public struct StaticDanmakuProvider: DanmakuProvider {
    private let storedComments: [DanmakuComment]

    public init(comments: [DanmakuComment]) {
        self.storedComments = comments
    }

    public func comments(for episode: AnimeEpisodeIdentity) async throws -> [DanmakuComment] {
        storedComments.sorted { $0.time < $1.time }
    }
}
