import Foundation

public protocol YouTubeVideoProvider: Sendable {
    var displayName: String { get }
    func search(query: String) async throws -> [YouTubeVideo]
}

public struct YouTubeDataAPIProvider: YouTubeVideoProvider {
    public let displayName = "YouTube Data API"
    private let credentials: YouTubeCredentials
    private let transport: any AnimeHTTPTransport

    public init(
        credentials: YouTubeCredentials,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public func search(query: String) async throws -> [YouTubeVideo] {
        let request = try YouTubeDataAPI.searchRequest(
            query: query,
            credentials: credentials,
            maxResults: 20
        )
        let data = try await transport.data(for: request)
        return try YouTubeDataAPI.decodeSearchResponse(data)
    }
}

public struct StaticYouTubeVideoProvider: YouTubeVideoProvider {
    public let displayName: String
    private let videos: [YouTubeVideo]

    public init(displayName: String = "YouTube 示範資料", videos: [YouTubeVideo]) {
        self.displayName = displayName
        self.videos = videos
    }

    public func search(query: String) async throws -> [YouTubeVideo] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return videos
        }
        return videos.filter { video in
            video.title.localizedCaseInsensitiveContains(trimmedQuery)
                || video.channelTitle.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

public enum YouTubeProviderFactory {
    public static func defaultProvider(
        credentials: YouTubeCredentials = .environment()
    ) -> any YouTubeVideoProvider {
        if credentials.isConfigured {
            return YouTubeDataAPIProvider(credentials: credentials)
        }
        return StaticYouTubeVideoProvider(displayName: "YouTube 未配置", videos: [])
    }

    public static func demoProvider() -> StaticYouTubeVideoProvider {
        StaticYouTubeVideoProvider(videos: [
            YouTubeVideo(
                id: "M7lc1UVf-VE",
                title: "YouTube IFrame API Demo",
                channelTitle: "Google Developers",
                description: "官方播放器 API 示範"
            ),
            YouTubeVideo(
                id: "dQw4w9WgXcQ",
                title: "Big Screen Music Demo",
                channelTitle: "YouTube",
                description: "示範播放項目"
            ),
            YouTubeVideo(
                id: "ScMzIvxBSi4",
                title: "TV Mode Sample",
                channelTitle: "YouTube",
                description: "示範遙控器播放流程"
            )
        ])
    }
}
