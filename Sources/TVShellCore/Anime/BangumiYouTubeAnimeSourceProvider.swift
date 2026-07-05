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
                episodes: episodes(for: subject)
            )
        }
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        let request = try YouTubeDataAPI.searchRequest(
            query: episode.title,
            credentials: youtubeCredentials,
            maxResults: 10
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
                    subjectID: "\(subject.id)",
                    episodeID: "\(number)"
                )
            )
        }
    }

    private func score(video: YouTubeVideo, episode: AnimeEpisode) -> Int {
        var value = 60
        if video.title.localizedCaseInsensitiveContains(episode.title) {
            value += 40
        }
        if video.title.contains("\(episode.number)") {
            value += 10
        }
        return value
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
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) -> any AnimeSourceProvider {
        let registry = AnimeSourceRegistry(adapters: [
            BangumiYouTubeAnimeSourceProvider(
                youtubeCredentials: youtubeCredentials,
                transport: transport
            )
        ])
        return CatalogAnimeSourceProvider(catalog: catalog, registry: registry)
    }
}
