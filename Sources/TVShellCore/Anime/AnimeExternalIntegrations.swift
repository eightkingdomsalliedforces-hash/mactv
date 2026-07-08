import CryptoKit
import Foundation

public struct AnimeHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct BangumiSubject: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var nameCN: String?
    public var summary: String?
    public var episodeCount: Int?
    public var images: BangumiSubjectImages?
    public var date: String?
    public var rating: BangumiSubjectRating?
    public var rank: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameCN = "name_cn"
        case summary
        case episodeCount = "eps"
        case images
        case date
        case rating
        case rank
    }

    public var title: String {
        let trimmedCN = nameCN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedCN.isEmpty ? name : trimmedCN
    }

    public var coverURL: URL? {
        images?.coverURL
    }
}

public struct BangumiSubjectRating: Codable, Equatable, Sendable {
    public var score: Double?
    public var total: Int?
}

public struct BangumiSubjectImages: Codable, Equatable, Sendable {
    public var large: String?
    public var common: String?
    public var medium: String?
    public var small: String?
    public var grid: String?

    public var coverURL: URL? {
        [large, common, medium, small, grid]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }
}

public enum BangumiAPI {
    public static let baseURL = URL(string: "https://api.bgm.tv")!

    public static func searchSubjectsRequest(keyword: String) throws -> AnimeHTTPRequest {
        let url = baseURL
            .appending(path: "/v0/search/subjects")
            .appending(queryItems: [
                URLQueryItem(name: "limit", value: "30")
            ])
        let payload = BangumiSubjectSearchPayload(
            keyword: keyword,
            filter: BangumiSubjectSearchFilter(type: [2])
        )
        let body = try JSONEncoder.tvShell.encode(payload)
        return AnimeHTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "TVShell/0.1 (macOS big-screen anime client)"
            ],
            body: body
        )
    }

    public static func decodeSubjectSearch(_ data: Data) throws -> [BangumiSubject] {
        try JSONDecoder().decode(BangumiSubjectSearchResponse.self, from: data).data
    }
}

private struct BangumiSubjectSearchPayload: Encodable {
    var keyword: String
    var filter: BangumiSubjectSearchFilter
}

private struct BangumiSubjectSearchFilter: Encodable {
    var type: [Int]
}

private struct BangumiSubjectSearchResponse: Decodable {
    var data: [BangumiSubject]
}

public enum DandanplaySignature {
    public static func signature(appID: String, timestamp: Int, path: String, appSecret: String) -> String {
        let input = "\(appID)\(timestamp)\(path)\(appSecret)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
    }
}

public enum DandanplayAPI {
    public static let baseURL = URL(string: "https://api.dandanplay.net")!

    public static func searchEpisodesRequest(
        anime: String,
        episode: Int,
        appID: String,
        appSecret: String,
        timestamp: Int
    ) -> AnimeHTTPRequest {
        let path = "/api/v2/search/episodes"
        let signature = DandanplaySignature.signature(
            appID: appID,
            timestamp: timestamp,
            path: path,
            appSecret: appSecret
        )
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "anime", value: anime),
            URLQueryItem(name: "episode", value: "\(episode)")
        ]
        return AnimeHTTPRequest(
            method: "GET",
            url: components.url!,
            headers: [
                "Accept": "application/json",
                "X-AppId": appID,
                "X-Timestamp": "\(timestamp)",
                "X-Signature": signature
            ]
        )
    }

    public static func commentRequest(
        episodeID: String,
        appID: String,
        appSecret: String,
        timestamp: Int
    ) -> AnimeHTTPRequest {
        let path = "/api/v2/comment/\(episodeID)"
        let signature = DandanplaySignature.signature(
            appID: appID,
            timestamp: timestamp,
            path: path,
            appSecret: appSecret
        )
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "withRelated", value: "true")]
        return AnimeHTTPRequest(
            method: "GET",
            url: components.url!,
            headers: [
                "Accept": "application/json",
                "X-AppId": appID,
                "X-Timestamp": "\(timestamp)",
                "X-Signature": signature
            ]
        )
    }

    public static func decodeComments(_ data: Data) throws -> [DanmakuComment] {
        try JSONDecoder().decode(DandanplayCommentResponse.self, from: data)
            .comments
            .compactMap(\.danmakuComment)
            .sorted { $0.time < $1.time }
    }

    public static func decodeEpisodeSearch(_ data: Data, preferredEpisode: Int) throws -> String? {
        let response = try JSONDecoder().decode(DandanplayEpisodeSearchResponse.self, from: data)
        let candidates = response.allEpisodes
        if let exact = candidates.first(where: { $0.matches(episode: preferredEpisode) }) {
            return exact.episodeIDString
        }
        return candidates.first?.episodeIDString
    }
}

private struct DandanplayEpisodeSearchResponse: Decodable {
    var animes: [DandanplaySearchAnime]?
    var episodes: [DandanplaySearchEpisode]?

    var allEpisodes: [DandanplaySearchEpisode] {
        if let episodes, episodes.isEmpty == false {
            return episodes
        }
        return animes?.flatMap(\.episodes) ?? []
    }
}

private struct DandanplaySearchAnime: Decodable {
    var episodes: [DandanplaySearchEpisode]
}

private struct DandanplaySearchEpisode: Decodable {
    var episodeID: Int?
    var episodeIDStringValue: String?
    var episodeTitle: String?
    var episodeNumber: String?

    enum CodingKeys: String, CodingKey {
        case episodeID = "episodeId"
        case episodeTitle
        case episodeNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodeID = try? container.decode(Int.self, forKey: .episodeID)
        episodeIDStringValue = try? container.decode(String.self, forKey: .episodeID)
        episodeTitle = try? container.decode(String.self, forKey: .episodeTitle)
        episodeNumber = try? container.decode(String.self, forKey: .episodeNumber)
    }

    var episodeIDString: String? {
        if let episodeID {
            return "\(episodeID)"
        }
        return episodeIDStringValue
    }

    func matches(episode: Int) -> Bool {
        if let episodeNumber,
           Int(episodeNumber.filter(\.isNumber)) == episode {
            return true
        }
        if let episodeTitle,
           Int(episodeTitle.filter(\.isNumber)) == episode {
            return true
        }
        return false
    }
}

private struct DandanplayCommentResponse: Decodable {
    var comments: [DandanplayRawComment]
}

private struct DandanplayRawComment: Decodable {
    var p: String
    var m: String

    var danmakuComment: DanmakuComment? {
        let fields = p.split(separator: ",")
        guard fields.count >= 4,
              let time = Double(fields[0]),
              let rawMode = Int(fields[1]),
              let colorValue = Int(fields[3])
        else {
            return nil
        }

        return DanmakuComment(
            time: time,
            text: m,
            colorHex: String(format: "#%06X", colorValue),
            mode: DanmakuMode(dandanplayMode: rawMode)
        )
    }
}

public enum DanmakuAggregator {
    public static func merge(_ groups: [[DanmakuComment]]) -> [DanmakuComment] {
        var seen = Set<String>()
        return groups
            .flatMap { $0 }
            .sorted { left, right in
                if left.time == right.time {
                    return left.text < right.text
                }
                return left.time < right.time
            }
            .filter { comment in
                let key = "\(String(format: "%.2f", comment.time))|\(comment.text)"
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }
}

public enum AnimeStreamSelector {
    public static func bestCandidate(from candidates: [AnimeStreamCandidate]) -> AnimeStreamCandidate? {
        candidates.max { left, right in
            score(left) < score(right)
        }
    }

    private static func score(_ candidate: AnimeStreamCandidate) -> Int {
        candidate.priority + qualityScore(candidate.quality)
    }

    private static func qualityScore(_ quality: String) -> Int {
        let lowercased = quality.lowercased()
        if lowercased.contains("2160") || lowercased.contains("4k") {
            return 45
        }
        if lowercased.contains("1080") {
            return 25
        }
        if lowercased.contains("720") {
            return 8
        }
        return 0
    }
}

private extension DanmakuMode {
    init(dandanplayMode: Int) {
        switch dandanplayMode {
        case 4, 5:
            self = .top
        case 6:
            self = .bottom
        default:
            self = .scroll
        }
    }
}

private extension JSONEncoder {
    static var tvShell: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
