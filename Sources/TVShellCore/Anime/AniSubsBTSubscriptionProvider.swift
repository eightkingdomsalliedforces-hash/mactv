import Foundation

public struct AniSubsBTSubscriptionProvider: AnimeMediaSourceAdapter {
    public let id = "ani-subs-bt"
    public let displayName = "ani-subs BT"
    public let resolverKind: AnimeResolverKind = .torrent

    private let subscriptionURL: URL
    private let transport: any AnimeHTTPTransport

    public init(
        subscriptionURL: URL = URL(string: "https://sub.creamycake.org/v1/bt1.json")!,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.subscriptionURL = subscriptionURL
        self.transport = transport
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let sources = try await rssSources()
        var allResults: [AnimeSearchResult] = []
        for source in sources {
            do {
                let provider = BTFeedAnimeSourceProvider(
                    id: "\(id)-\(stableID(source.name))",
                    displayName: source.name,
                    searchURLTemplate: source.searchURLTemplate,
                    transport: transport
                )
                let results = try await provider.search(query)
                allResults.append(contentsOf: results.map { rewrite(result: $0, sourceName: source.name) })
            } catch {
                continue
            }
        }
        return Array(mergeAniSubsResults(allResults).prefix(60))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes.sorted { $0.number < $1.number }
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let url = episode.identity.playbackURL else {
            throw AnimeHTTPError.missingRoute("ani-subs playback url: \(episode.identity.episodeID)")
        }
        return [
            AnimeStreamCandidate(
                url: url,
                quality: "ani-subs BT",
                priority: 58,
                headers: [
                    "resolver": "torrent",
                    "source": displayName,
                    "title": episode.identity.subjectID,
                    "episode": episode.title
                ]
            )
        ]
    }

    private func rssSources() async throws -> [AniSubsRSSSource] {
        let data = try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: subscriptionURL,
            headers: [
                "Accept": "application/json",
                "User-Agent": "TVShell/0.1 ani-subs"
            ]
        ))
        return try AniSubsBTSubscription.decode(data)
    }

    private func rewrite(result: AnimeSearchResult, sourceName: String) -> AnimeSearchResult {
        let episodes = result.episodes.map { episode in
            AnimeEpisode(
                id: "\(id)-\(stableID(sourceName))-\(episode.id)",
                title: episode.title,
                number: episode.number,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: result.title,
                    episodeID: episode.identity.episodeID,
                    subjectAliases: episode.identity.subjectAliases,
                    playbackURL: episode.identity.playbackURL
                )
            )
        }
        return AnimeSearchResult(
            id: "\(id)-\(stableID(sourceName))-\(result.id)",
            title: result.title,
            subtitle: "\(sourceName) · \(result.subtitle ?? "BT 訂閱")",
            coverURL: result.coverURL,
            originalTitle: result.originalTitle,
            airDate: result.airDate,
            score: result.score,
            rank: result.rank,
            episodeCount: result.episodeCount,
            episodes: episodes
        )
    }

    private func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

public struct AniSubsRSSSource: Equatable, Sendable {
    public var name: String
    public var searchURLTemplate: String
}

private enum AniSubsBTSubscription {
    static func decode(_ data: Data) throws -> [AniSubsRSSSource] {
        let response = try JSONDecoder().decode(AniSubsBTResponse.self, from: data)
        return response.exportedMediaSourceDataList.mediaSources.compactMap { source in
            guard source.factoryId == "rss",
                  let name = source.arguments.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.isEmpty == false,
                  let searchURL = source.arguments.searchConfig?.searchUrl,
                  searchURL.contains("{keyword}")
            else {
                return nil
            }
            return AniSubsRSSSource(name: name, searchURLTemplate: searchURL)
        }
    }
}

private func mergeAniSubsResults(_ results: [AnimeSearchResult]) -> [AnimeSearchResult] {
    var byTitle: [String: AnimeSearchResult] = [:]
    var order: [String] = []
    for result in results {
        let key = result.title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if var existing = byTitle[key] {
            let episodes = (existing.episodes + result.episodes).sorted { $0.number < $1.number }
            var seen = Set<Int>()
            existing.episodes = episodes.filter { seen.insert($0.number).inserted }
            existing.episodeCount = existing.episodes.count
            byTitle[key] = existing
        } else {
            byTitle[key] = result
            order.append(key)
        }
    }
    return order.compactMap { byTitle[$0] }
}

private struct AniSubsBTResponse: Decodable {
    var exportedMediaSourceDataList: AniSubsMediaSourceList
}

private struct AniSubsMediaSourceList: Decodable {
    var mediaSources: [AniSubsMediaSource]
}

private struct AniSubsMediaSource: Decodable {
    var factoryId: String
    var arguments: AniSubsMediaSourceArguments
}

private struct AniSubsMediaSourceArguments: Decodable {
    var name: String?
    var searchConfig: AniSubsSearchConfig?
}

private struct AniSubsSearchConfig: Decodable {
    var searchUrl: String
}
