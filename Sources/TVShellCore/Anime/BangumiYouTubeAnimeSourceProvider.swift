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
        return try YouTubeDataAPI.decodeSearchResponse(data)
            .filter { isPlayableEpisodeMatch(video: $0, episode: episode) }
            .map { video in
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
        let aliases = subjectAliases(for: subject)
        return (1...count).map { number in
            let episodeTitle = "\(subject.title) 第 \(number) 話"
            return AnimeEpisode(
                id: "bangumi-\(subject.id)-episode-\(number)",
                title: episodeTitle,
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: subject.title,
                    episodeID: "\(number)",
                    subjectAliases: aliases
                )
            )
        }
    }

    private func subjectAliases(for subject: BangumiSubject) -> [String] {
        uniqueNonEmpty([subject.title, subject.name])
    }

    private func score(video: YouTubeVideo, episode: AnimeEpisode) -> Int {
        var value = 40
        let title = video.title
        if hasSubjectMatch(title: title, episode: episode) {
            value += 40
        }
        if matchesEpisodeNumber(title, episode: episode.number) {
            value += 44
        }
        if isAuthorizedAnimeChannel(video.channelTitle) {
            value += 80
        }
        if isExcludedClip(title) {
            value -= 70
        }
        return value
    }

    private func youtubeSearchQuery(for episode: AnimeEpisode) -> String {
        "\(subjectSearchText(for: episode)) 第\(episode.number)話 EP\(episode.number) 木棉花 Muse Ani-One 羚邦 動畫"
    }

    private func isPlayableEpisodeMatch(video: YouTubeVideo, episode: AnimeEpisode) -> Bool {
        let title = video.title
        return hasSubjectMatch(title: title, episode: episode)
            && matchesEpisodeNumber(title, episode: episode.number)
            && isAuthorizedAnimeChannel(video.channelTitle)
            && isExcludedClip(title) == false
    }

    private func isAuthorizedAnimeChannel(_ channelTitle: String) -> Bool {
        let licensedTerms = [
            "木棉花",
            "Muse",
            "Muse Asia",
            "Muse木棉花",
            "Ani-One",
            "Ani-One Asia",
            "羚邦",
            "Medialink",
            "KADOKAWA",
            "BANDAI",
            "Toei",
            "Crunchyroll"
        ]
        return licensedTerms.contains { channelTitle.localizedCaseInsensitiveContains($0) }
    }

    private func hasSubjectMatch(title: String, episode: AnimeEpisode) -> Bool {
        subjectMatchTerms(for: episode).contains { term in
            title.localizedCaseInsensitiveContains(term)
        }
    }

    private func subjectSearchText(for episode: AnimeEpisode) -> String {
        uniqueNonEmpty([episode.identity.subjectID] + episode.identity.subjectAliases)
            .joined(separator: " ")
    }

    private func subjectMatchTerms(for episode: AnimeEpisode) -> [String] {
        uniqueNonEmpty([episode.identity.subjectID] + episode.identity.subjectAliases)
            .flatMap(matchTerms)
    }

    private func matchTerms(from alias: String) -> [String] {
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return []
        }

        var terms = [trimmed]
        if let range = trimmed.range(of: "的") {
            let suffix = String(trimmed[range.upperBound...])
            if suffix.count >= 2 {
                terms.append(suffix)
            }
        }
        terms += trimmed
            .split { $0.isWhitespace || $0 == ":" || $0 == "-" || $0 == "_" || $0 == "・" }
            .map(String.init)
            .filter { $0.count >= 4 || $0.rangeOfCharacter(from: .letters) != nil && $0.count >= 3 }
        return uniqueNonEmpty(terms)
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

    private func isExcludedClip(_ title: String) -> Bool {
        title.localizedCaseInsensitiveContains("reaction") ||
            title.localizedCaseInsensitiveContains("解說") ||
            title.localizedCaseInsensitiveContains("預告") ||
            title.localizedCaseInsensitiveContains("trailer") ||
            title.localizedCaseInsensitiveContains("shorts") ||
            title.localizedCaseInsensitiveContains("short") ||
            title.localizedCaseInsensitiveContains("精華") ||
            title.localizedCaseInsensitiveContains("剪輯") ||
            title.localizedCaseInsensitiveContains("片段")
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var results: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                continue
            }
            let key = trimmed.lowercased()
            guard seen.contains(key) == false else {
                continue
            }
            seen.insert(key)
            results.append(trimmed)
        }
        return results
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
        selectorConfigs: [SelectorAnimeSourceConfig] = (try? SelectorAnimeSourceConfig.environment()) ?? [],
        mediaServerConfigs: [MediaServerAnimeSourceConfig] = MediaServerAnimeSourceConfig.environment()
    ) -> any AnimeSourceProvider {
        let selectorAdapters = selectorConfigs.map { config in
            SelectorAnimeSourceProvider(config: config, transport: transport) as any AnimeMediaSourceAdapter
        }
        let mediaServerAdapters = mediaServerConfigs.map { config in
            MediaServerAnimeSourceProvider(config: config, transport: transport) as any AnimeMediaSourceAdapter
        }
        let adapters: [any AnimeMediaSourceAdapter] = [
            BangumiYouTubeAnimeSourceProvider(
                youtubeCredentials: youtubeCredentials,
                transport: transport
            ),
            BTFeedAnimeSourceProvider(
                id: "mikan",
                displayName: "Mikan Project",
                searchURLTemplate: "https://mikanani.me/RSS/Search?searchstr={keyword}",
                transport: transport
            ),
            BTFeedAnimeSourceProvider(
                id: "dmhy",
                displayName: "動漫花園",
                searchURLTemplate: "https://share.dmhy.org/topics/rss/rss.xml?keyword={keyword}",
                transport: transport
            )
        ] + mediaServerAdapters + selectorAdapters
        let registry = AnimeSourceRegistry(adapters: adapters)
        let catalogProvider = CatalogAnimeSourceProvider(
            catalog: catalog
                .includingDynamicDefinitions(mediaServerConfigs.map(\.catalogDefinition))
                .includingDynamicDefinitions(selectorConfigs.map(\.catalogDefinition)),
            registry: registry
        )
        return AnimeHomeSourceProvider(base: catalogProvider)
    }
}
