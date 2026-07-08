import Foundation

public enum BilibiliAPIError: Error, Equatable, LocalizedError, Sendable {
    case api(code: Int, message: String)
    case missingData(String)

    public var errorDescription: String? {
        switch self {
        case let .api(code, message):
            "Bilibili API 錯誤 \(code)：\(message)"
        case let .missingData(label):
            "Bilibili 回傳缺少資料：\(label)"
        }
    }
}

public protocol BilibiliBangumiProviding: Sendable {
    var displayName: String { get }
    func home() async throws -> [BilibiliSeason]
    func search(keyword: String) async throws -> [BilibiliSeason]
    func detail(seasonID: Int) async throws -> BilibiliSeasonDetail
    func playback(episode: BilibiliEpisode) async throws -> BilibiliPlaybackStream
}

public struct BilibiliBangumiProvider: BilibiliBangumiProviding {
    public let displayName = "Bilibili PGC API"
    private let transport: any AnimeHTTPTransport

    public init(transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()) {
        self.transport = transport
    }

    public func home() async throws -> [BilibiliSeason] {
        let data = try await transport.data(for: BilibiliAPI.homeRequest())
        return try BilibiliAPI.decodeHome(data)
    }

    public func search(keyword: String) async throws -> [BilibiliSeason] {
        let data = try await transport.data(for: BilibiliAPI.searchBangumiRequest(keyword: keyword))
        return try BilibiliAPI.decodeSearch(data)
    }

    public func detail(seasonID: Int) async throws -> BilibiliSeasonDetail {
        let data = try await transport.data(for: BilibiliAPI.seasonDetailRequest(seasonID: seasonID))
        return try BilibiliAPI.decodeSeasonDetail(data)
    }

    public func playback(episode: BilibiliEpisode) async throws -> BilibiliPlaybackStream {
        let data = try await transport.data(for: BilibiliAPI.playURLRequest(episode: episode))
        return try BilibiliAPI.decodePlayback(data)
    }
}

public enum BilibiliProviderFactory {
    public static func defaultProvider() -> any BilibiliBangumiProviding {
        BilibiliBangumiProvider()
    }
}

public enum BilibiliAPI {
    public static func homeRequest(cursor: String = "0") -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/pgc/page/pc/bangumi/tab")!
            .appending(queryItems: [
                URLQueryItem(name: "mobi_app", value: "android"),
                URLQueryItem(name: "build", value: "8130300"),
                URLQueryItem(name: "is_refresh", value: "0"),
                URLQueryItem(name: "cursor", value: cursor)
            ])
        return request(url)
    }

    public static func searchBangumiRequest(keyword: String, page: Int = 1) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/search/type")!
            .appending(queryItems: [
                URLQueryItem(name: "search_type", value: "media_bangumi"),
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "\(max(page, 1))"),
                URLQueryItem(name: "order", value: "totalrank")
            ])
        return request(url)
    }

    public static func seasonDetailRequest(seasonID: Int) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/pgc/view/web/season")!
            .appending(queryItems: [URLQueryItem(name: "season_id", value: "\(seasonID)")])
        return request(url)
    }

    public static func playURLRequest(episode: BilibiliEpisode) -> AnimeHTTPRequest {
        var items = [
            URLQueryItem(name: "ep_id", value: "\(episode.id)"),
            URLQueryItem(name: "qn", value: "80"),
            URLQueryItem(name: "fnver", value: "0"),
            URLQueryItem(name: "fnval", value: "0"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if let cid = episode.cid {
            items.append(URLQueryItem(name: "cid", value: "\(cid)"))
        }
        let url = URL(string: "https://api.bilibili.com/pgc/player/web/playurl")!
            .appending(queryItems: items)
        return request(url)
    }

    public static func decodeHome(_ data: Data) throws -> [BilibiliSeason] {
        let response = try JSONDecoder().decode(BilibiliHomeResponse.self, from: data)
        try check(code: response.code, message: response.message)
        let modules = response.data?.modules ?? []
        return uniqueSeasons(modules.flatMap { module in
            module.items.compactMap { item in item.season }
        })
    }

    public static func decodeSearch(_ data: Data) throws -> [BilibiliSeason] {
        let response = try JSONDecoder().decode(BilibiliSearchResponse.self, from: data)
        try check(code: response.code, message: response.message)
        return uniqueSeasons(response.data?.result.compactMap(\.season) ?? [])
    }

    public static func decodeSeasonDetail(_ data: Data) throws -> BilibiliSeasonDetail {
        let response = try JSONDecoder().decode(BilibiliSeasonDetailResponse.self, from: data)
        try check(code: response.code, message: response.message)
        guard let result = response.result else {
            throw BilibiliAPIError.missingData("season detail")
        }
        return result.detail
    }

    public static func decodePlayback(_ data: Data) throws -> BilibiliPlaybackStream {
        let response = try JSONDecoder().decode(BilibiliPlayURLResponse.self, from: data)
        try check(code: response.code, message: response.message)
        guard let result = response.result ?? response.data else {
            throw BilibiliAPIError.missingData("playurl")
        }
        guard let url = result.primaryURL else {
            throw BilibiliAPIError.missingData("playurl stream")
        }
        return BilibiliPlaybackStream(
            url: url,
            quality: result.qualityLabel,
            headers: playbackHeaders,
            durationSeconds: result.duration.map { Double($0) / 1000 }
        )
    }

    private static var playbackHeaders: [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15",
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com"
        ]
    }

    private static func request(_ url: URL) -> AnimeHTTPRequest {
        AnimeHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/json,text/plain,*/*",
                "User-Agent": playbackHeaders["User-Agent"] ?? "Mozilla/5.0",
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com"
            ]
        )
    }

    private static func check(code: Int, message: String?) throws {
        guard code == 0 else {
            throw BilibiliAPIError.api(code: code, message: message ?? "unknown")
        }
    }

    private static func uniqueSeasons(_ seasons: [BilibiliSeason]) -> [BilibiliSeason] {
        var seen = Set<Int>()
        return seasons.filter { seen.insert($0.id).inserted }
    }
}

private struct BilibiliHomeResponse: Decodable {
    var code: Int
    var message: String?
    var data: BilibiliHomeData?
}

private struct BilibiliHomeData: Decodable {
    var modules: [BilibiliHomeModule]
}

private struct BilibiliHomeModule: Decodable {
    var items: [BilibiliHomeItem]
}

private struct BilibiliHomeItem: Decodable {
    var title: String?
    var cover: String?
    var desc: String?
    var linkValue: Int?
    var seasonID: Int?
    var oid: Int?
    var badgeInfo: BilibiliBadgeInfo?
    var bottomRightBadge: BilibiliBadgeInfo?

    enum CodingKeys: String, CodingKey {
        case title
        case cover
        case desc
        case linkValue = "link_value"
        case seasonID = "season_id"
        case oid
        case badgeInfo = "badge_info"
        case bottomRightBadge = "bottom_right_badge"
    }

    var season: BilibiliSeason? {
        guard let id = linkValue ?? seasonID ?? oid,
              let title = title?.cleanBilibiliHTML,
              title.isEmpty == false
        else {
            return nil
        }
        return BilibiliSeason(
            id: id,
            title: title,
            subtitle: desc?.cleanBilibiliHTML,
            coverURL: cover.flatMap(URL.init(string:)),
            badge: badgeInfo?.text?.cleanBilibiliHTML,
            totalText: bottomRightBadge?.text?.cleanBilibiliHTML
        )
    }
}

private struct BilibiliSearchResponse: Decodable {
    var code: Int
    var message: String?
    var data: BilibiliSearchData?
}

private struct BilibiliSearchData: Decodable {
    var result: [BilibiliSearchItem]
}

private struct BilibiliSearchItem: Decodable {
    var seasonID: Int?
    var title: String?
    var cover: String?
    var indexShow: String?
    var seasonTypeName: String?
    var badge: String?

    enum CodingKeys: String, CodingKey {
        case seasonID = "season_id"
        case title
        case cover
        case indexShow = "index_show"
        case seasonTypeName = "season_type_name"
        case badge
    }

    var season: BilibiliSeason? {
        guard let seasonID,
              let title = title?.cleanBilibiliHTML,
              title.isEmpty == false
        else {
            return nil
        }
        return BilibiliSeason(
            id: seasonID,
            title: title,
            subtitle: seasonTypeName,
            coverURL: cover.flatMap(URL.init(string:)),
            badge: badge?.cleanBilibiliHTML,
            totalText: indexShow?.cleanBilibiliHTML
        )
    }
}

private struct BilibiliSeasonDetailResponse: Decodable {
    var code: Int
    var message: String?
    var result: BilibiliSeasonDetailPayload?
}

private struct BilibiliSeasonDetailPayload: Decodable {
    var seasonID: Int?
    var title: String?
    var seasonTitle: String?
    var cover: String?
    var subtitle: String?
    var evaluate: String?
    var rating: BilibiliRating?
    var stat: BilibiliStat?
    var episodes: [BilibiliEpisodePayload]?

    enum CodingKeys: String, CodingKey {
        case seasonID = "season_id"
        case title
        case seasonTitle = "season_title"
        case cover
        case subtitle
        case evaluate
        case rating
        case stat
        case episodes
    }

    var detail: BilibiliSeasonDetail {
        let parsedEpisodes = (episodes ?? []).enumerated().compactMap { offset, payload in
            payload.episode(defaultNumber: offset + 1)
        }
        return BilibiliSeasonDetail(
            id: seasonID ?? 0,
            title: (title ?? seasonTitle ?? "Bilibili 番劇").cleanBilibiliHTML,
            coverURL: cover.flatMap(URL.init(string:)),
            subtitle: subtitle?.cleanBilibiliHTML,
            evaluate: evaluate?.cleanBilibiliHTML,
            ratingScore: rating?.score,
            views: stat?.views ?? stat?.view,
            danmaku: stat?.danmakus ?? stat?.danmaku,
            episodes: parsedEpisodes
        )
    }
}

private struct BilibiliEpisodePayload: Decodable {
    var id: Int?
    var epID: Int?
    var aid: Int?
    var avid: Int?
    var cid: Int?
    var bvid: String?
    var title: String?
    var longTitle: String?
    var cover: String?
    var badge: String?
    var badgeInfo: BilibiliBadgeInfo?

    enum CodingKeys: String, CodingKey {
        case id
        case epID = "ep_id"
        case aid
        case avid
        case cid
        case bvid
        case title
        case longTitle = "long_title"
        case cover
        case badge
        case badgeInfo = "badge_info"
    }

    func episode(defaultNumber: Int) -> BilibiliEpisode? {
        guard let id = id ?? epID else {
            return nil
        }
        let rawTitle = title?.cleanBilibiliHTML ?? "\(defaultNumber)"
        return BilibiliEpisode(
            id: id,
            aid: aid ?? avid,
            cid: cid,
            bvid: bvid,
            title: rawTitle,
            longTitle: longTitle?.cleanBilibiliHTML ?? "",
            coverURL: cover.flatMap(URL.init(string:)),
            badge: badgeInfo?.text?.cleanBilibiliHTML ?? badge?.cleanBilibiliHTML,
            number: Int(rawTitle.filter(\.isNumber)) ?? defaultNumber
        )
    }
}

private struct BilibiliBadgeInfo: Decodable {
    var text: String?
}

private struct BilibiliRating: Decodable {
    var score: Double?
}

private struct BilibiliStat: Decodable {
    var views: Int?
    var view: Int?
    var danmakus: Int?
    var danmaku: Int?
}

private struct BilibiliPlayURLResponse: Decodable {
    var code: Int
    var message: String?
    var result: BilibiliPlayURLResult?
    var data: BilibiliPlayURLResult?
}

private struct BilibiliPlayURLResult: Decodable {
    var quality: Int?
    var format: String?
    var duration: Int?
    var durl: [BilibiliDURL]?
    var dash: BilibiliDASH?
    var acceptDescription: [String]?

    enum CodingKeys: String, CodingKey {
        case quality
        case format
        case duration
        case durl
        case dash
        case acceptDescription = "accept_description"
    }

    var primaryURL: URL? {
        let progressive = durl?
            .flatMap { [$0.url] + ($0.backupURL ?? []) }
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
        if let progressive {
            return progressive
        }
        return dash?.video?
            .flatMap { [$0.baseURL, $0.baseUrl] + ($0.backupURL ?? []) }
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
    }

    var qualityLabel: String {
        acceptDescription?.first ?? format ?? quality.map { "\($0)P" } ?? "Bilibili"
    }
}

private struct BilibiliDURL: Decodable {
    var url: String?
    var backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case backupURL = "backup_url"
    }
}

private struct BilibiliDASH: Decodable {
    var video: [BilibiliDASHVideo]?
}

private struct BilibiliDASHVideo: Decodable {
    var baseURL: String?
    var baseUrl: String?
    var backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case baseUrl = "baseUrl"
        case backupURL = "backup_url"
    }
}

private extension String {
    var cleanBilibiliHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
