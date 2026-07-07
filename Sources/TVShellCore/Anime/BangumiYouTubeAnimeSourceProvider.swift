import Foundation

public enum AnimeResolverKind: String, Codable, Equatable, Sendable {
    case http
    case youtube
    case webView
    case torrent
}

public protocol AnimeMediaSourceAdapter: AnimeSourceProvider {
    var resolverKind: AnimeResolverKind { get }
}

public struct BangumiYouTubeAnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id = "bangumi-youtube"
    public let displayName = "Bangumi + YouTube"
    public let resolverKind: AnimeResolverKind = .youtube

    private let youtubeCredentials: YouTubeCredentials
    private let transport: any AnimeHTTPTransport

    public init(
        youtubeCredentials: YouTubeCredentials,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.youtubeCredentials = youtubeCredentials
        self.transport = transport
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let request = try BangumiAPI.searchSubjectsRequest(keyword: query.keyword)
        let data = try await transport.data(for: request)
        let subjects = try BangumiAPI.decodeSubjectSearch(data)
        return subjects.map { subject in
            AnimeSearchResult(
                id: "bangumi-\(subject.id)",
                title: subject.title,
                subtitle: subject.summary,
                coverURL: subject.coverURL,
                originalTitle: subject.name,
                airDate: subject.date,
                score: subject.rating?.score,
                rank: subject.rank,
                episodeCount: subject.episodeCount,
                episodes: episodes(for: subject)
            )
        }
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        let request = try YouTubeDataAPI.searchRequest(
            query: youtubeSearchQuery(for: episode),
            credentials: youtubeCredentials,
            maxResults: 10,
            profile: .animeEpisode
        )
        let data = try await transport.data(for: request)
        return try YouTubeDataAPI.decodeSearchResponse(data).map { video in
            AnimeStreamCandidate(
                url: URL(string: "youtube://\(video.id)")!,
                quality: "YouTube",
                priority: score(video: video, episode: episode),
                headers: [
                    "title": video.title,
                    "channel": video.channelTitle
                ]
            )
        }
        .sorted { $0.priority > $1.priority }
    }

    private func episodes(for subject: BangumiSubject) -> [AnimeEpisode] {
        let count = max(subject.episodeCount ?? 1, 1)
        return (1...count).map { number in
            let episodeTitle = "\(subject.title) 第 \(number) 話"
            return AnimeEpisode(
                id: "bangumi-\(subject.id)-episode-\(number)",
                title: episodeTitle,
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: subject.title,
                    episodeID: "\(number)"
                )
            )
        }
    }

    private func score(video: YouTubeVideo, episode: AnimeEpisode) -> Int {
        var value = 40
        let title = video.title
        if title.localizedCaseInsensitiveContains(episode.identity.subjectID) {
            value += 40
        }
        if matchesEpisodeNumber(title, episode: episode.number) {
            value += 44
        }
        if title.localizedCaseInsensitiveContains("reaction") ||
            title.localizedCaseInsensitiveContains("解說") ||
            title.localizedCaseInsensitiveContains("預告") ||
            title.localizedCaseInsensitiveContains("trailer") ||
            title.localizedCaseInsensitiveContains("shorts") ||
            title.localizedCaseInsensitiveContains("short") ||
            title.localizedCaseInsensitiveContains("精華") ||
            title.localizedCaseInsensitiveContains("剪輯") ||
            title.localizedCaseInsensitiveContains("片段") {
            value -= 70
        }
        return value
    }

    private func youtubeSearchQuery(for episode: AnimeEpisode) -> String {
        "\(episode.identity.subjectID) 第\(episode.number)話 EP\(episode.number) 完整版 動畫"
    }

    private func matchesEpisodeNumber(_ title: String, episode: Int) -> Bool {
        [
            "第 \(episode) 話",
            "第\(episode)話",
            "第 \(episode) 集",
            "第\(episode)集",
            "EP\(episode)",
            "E\(episode)",
            "Episode \(episode)"
        ].contains { title.localizedCaseInsensitiveContains($0) }
    }
}

public enum AnimeSourceProviderFactory {
    public static func defaultProvider(
        youtubeCredentials: YouTubeCredentials = .environment()
    ) -> any AnimeSourceProvider {
        BangumiYouTubeAnimeSourceProvider(youtubeCredentials: youtubeCredentials)
    }

    public static func provider(
        catalog: AnimeSourceCatalogState,
        youtubeCredentials: YouTubeCredentials = .environment(),
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport(),
        selectorConfigs: [SelectorAnimeSourceConfig] = (try? SelectorAnimeSourceConfig.environment()) ?? []
    ) -> any AnimeSourceProvider {
        let selectorAdapters = selectorConfigs.map { config in
            SelectorAnimeSourceProvider(config: config, transport: transport) as any AnimeMediaSourceAdapter
        }
        let adapters: [any AnimeMediaSourceAdapter] = [
            BangumiYouTubeAnimeSourceProvider(
                youtubeCredentials: youtubeCredentials,
                transport: transport
            )
        ] + selectorAdapters
        let registry = AnimeSourceRegistry(adapters: adapters)
        let catalogProvider = CatalogAnimeSourceProvider(
            catalog: catalog.includingDynamicDefinitions(selectorConfigs.map(\.catalogDefinition)),
            registry: registry
        )
        return AnimeHomeSourceProvider(base: catalogProvider)
    }
}
