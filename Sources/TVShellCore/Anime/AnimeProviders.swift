import CoreFoundation
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

public struct AnimeHomeSourceProvider: AnimeSourceProvider {
    public let id: String
    public let displayName: String

    private let base: any AnimeSourceProvider
    private let homeKeywords: [String]

    public init(
        base: any AnimeSourceProvider,
        homeKeywords: [String] = AnimeSearchKeywordCatalog.defaultKeywords
    ) {
        self.base = base
        self.homeKeywords = homeKeywords
        id = "\(base.id)-home"
        displayName = base.displayName
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty else {
            return try await searchWithSimplifiedFallback(keyword)
        }

        var matches: [(Int, AnimeSearchResult)] = []
        for (index, homeKeyword) in homeKeywords.enumerated() {
            do {
                let candidates = try await searchWithSimplifiedFallback(homeKeyword)
                if let result = bestHomeCandidate(from: candidates, keyword: homeKeyword) {
                    matches.append((index, result))
                }
            } catch {
                continue
            }
        }

        var seenTitles = Set<String>()
        var results: [AnimeSearchResult] = []
        for (_, best) in matches {
            let normalized = normalizeTitle(best.title)
            guard seenTitles.contains(normalized) == false else {
                continue
            }
            seenTitles.insert(normalized)
            results.append(best)
        }
        return results
    }

    private func searchWithSimplifiedFallback(_ keyword: String) async throws -> [AnimeSearchResult] {
        if let results = try? await base.search(AnimeSearchQuery(keyword: keyword)), results.isEmpty == false {
            return results
        }

        let simplified = simplifiedChinese(keyword)
        guard simplified != keyword,
              let results = try? await base.search(AnimeSearchQuery(keyword: simplified)),
              results.isEmpty == false
        else {
            throw AnimeSourceCatalogError.noPlayableAdapter
        }
        return results
    }

    private func simplifiedChinese(_ value: String) -> String {
        let mutable = NSMutableString(string: value)
        CFStringTransform(mutable, nil, "Traditional-Simplified" as CFString, false)
        return mutable as String
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        try await base.episodes(for: result)
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        try await base.streams(for: episode)
    }

    private func bestHomeCandidate(from candidates: [AnimeSearchResult], keyword: String) -> AnimeSearchResult? {
        var best: AnimeSearchResult?
        var bestScore = Int.min
        for candidate in candidates {
            let candidateScore = score(candidate, keyword: keyword)
            if candidateScore > bestScore {
                best = candidate
                bestScore = candidateScore
            }
        }
        return best
    }

    private func score(_ result: AnimeSearchResult, keyword: String) -> Int {
        var value = 0
        if result.title.compare(keyword, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            value += 120
        }
        if result.title.localizedCaseInsensitiveContains(keyword) {
            value += 40
        }
        if result.title.count <= keyword.count + 2 {
            value += 20
        }
        if result.title.contains("第二季") || result.title.contains("第2季") || result.title.localizedCaseInsensitiveContains("Season 2") {
            value -= 35
        }
        if let score = result.score {
            value += Int(score * 10)
        }
        if result.coverURL != nil {
            value += 8
        }
        if let rank = result.rank {
            value += max(0, 30 - min(rank / 100, 30))
        }
        return value
    }

    private func normalizeTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "第二季", with: "")
            .replacingOccurrences(of: "第2季", with: "")
            .replacingOccurrences(of: "Season 2", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "S2", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
