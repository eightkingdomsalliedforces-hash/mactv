import Foundation

public enum YouTubeDataAPI {
    public static let baseURL = URL(string: "https://www.googleapis.com/youtube/v3")!

    public enum SearchProfile: Equatable, Sendable {
        case general
        case animeEpisode
    }

    public static func searchRequest(
        query: String,
        credentials: YouTubeCredentials,
        maxResults: Int = 20,
        profile: SearchProfile = .general
    ) throws -> AnimeHTTPRequest {
        guard credentials.isConfigured else {
            throw YouTubeAPIError.missingAPIKey
        }

        var components = URLComponents(url: baseURL.appending(path: "/search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "\(max(1, min(maxResults, 50)))"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "videoSyndicated", value: "true"),
            URLQueryItem(name: "key", value: credentials.apiKey)
        ]
        if profile == .animeEpisode {
            queryItems.append(URLQueryItem(name: "videoDuration", value: "long"))
        }
        components.queryItems = queryItems

        return AnimeHTTPRequest(
            method: "GET",
            url: components.url!,
            headers: [
                "Accept": "application/json",
                "User-Agent": "TVShell/0.1 (macOS big-screen YouTube client)"
            ]
        )
    }

    public static func decodeSearchResponse(_ data: Data) throws -> [YouTubeVideo] {
        try JSONDecoder().decode(YouTubeSearchResponse.self, from: data)
            .items
            .compactMap(\.video)
    }
}

public enum YouTubeAPIError: Error, Equatable, Sendable {
    case missingAPIKey
}

private struct YouTubeSearchResponse: Decodable {
    var items: [YouTubeSearchItem]
}

private struct YouTubeSearchItem: Decodable {
    var id: YouTubeSearchID
    var snippet: YouTubeSnippet

    var video: YouTubeVideo? {
        guard let videoID = id.videoID else {
            return nil
        }
        return YouTubeVideo(
            id: videoID,
            title: snippet.title,
            channelTitle: snippet.channelTitle,
            description: snippet.description ?? "",
            thumbnailURL: snippet.bestThumbnailURL
        )
    }
}

private struct YouTubeSearchID: Decodable {
    var videoID: String?

    enum CodingKeys: String, CodingKey {
        case videoID = "videoId"
    }
}

private struct YouTubeSnippet: Decodable {
    var title: String
    var channelTitle: String
    var description: String?
    var thumbnails: [String: YouTubeThumbnail]?

    var bestThumbnailURL: URL? {
        ["maxres", "high", "medium", "default"]
            .compactMap { thumbnails?[$0]?.url }
            .first
    }
}

private struct YouTubeThumbnail: Decodable {
    var url: URL
}
