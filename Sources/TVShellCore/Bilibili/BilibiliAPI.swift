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
    func detail(item: BilibiliSeason) async throws -> BilibiliSeasonDetail
    func detail(seasonID: Int) async throws -> BilibiliSeasonDetail
    func playback(episode: BilibiliEpisode) async throws -> BilibiliPlaybackStream
}

public struct BilibiliBangumiProvider: BilibiliBangumiProviding {
    public let displayName = "Bilibili PGC API"
    private let transport: any AnimeHTTPTransport
    private let credentials: BilibiliCredentials

    public init(
        credentials: BilibiliCredentials = .environment(),
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public func home() async throws -> [BilibiliSeason] {
        async let bangumiData = transport.data(for: BilibiliAPI.homeRequest(credentials: credentials))
        async let popularData = transport.data(for: BilibiliAPI.popularVideoRequest(credentials: credentials))
        var results: [BilibiliSeason] = []
        if let bangumi = try? await BilibiliAPI.decodeHome(bangumiData) {
            results.append(contentsOf: bangumi)
        }
        if let videos = try? await BilibiliAPI.decodePopularVideos(popularData) {
            results.append(contentsOf: videos)
        }
        return BilibiliAPI.uniqueItems(results)
    }

    public func search(keyword: String) async throws -> [BilibiliSeason] {
        async let bangumiData = transport.data(for: BilibiliAPI.searchBangumiRequest(keyword: keyword, credentials: credentials))
        async let videoData = transport.data(for: BilibiliAPI.searchVideoRequest(keyword: keyword, credentials: credentials))
        var results: [BilibiliSeason] = []
        if let bangumi = try? await BilibiliAPI.decodeSearch(bangumiData) {
            results.append(contentsOf: bangumi)
        }
        if let videos = try? await BilibiliAPI.decodeVideoSearch(videoData) {
            results.append(contentsOf: videos)
        }
        return BilibiliAPI.uniqueItems(results)
    }

    public func detail(item: BilibiliSeason) async throws -> BilibiliSeasonDetail {
        switch item.itemKind {
        case .bangumi:
            return try await detail(seasonID: item.id)
        case .video:
            let data = try await transport.data(for: BilibiliAPI.videoDetailRequest(item: item, credentials: credentials))
            return try BilibiliAPI.decodeVideoDetail(data)
        }
    }

    public func detail(seasonID: Int) async throws -> BilibiliSeasonDetail {
        let data = try await transport.data(for: BilibiliAPI.seasonDetailRequest(seasonID: seasonID, credentials: credentials))
        return try BilibiliAPI.decodeSeasonDetail(data)
    }

    public func playback(episode: BilibiliEpisode) async throws -> BilibiliPlaybackStream {
        let data = try await transport.data(for: BilibiliAPI.playURLRequest(episode: episode, credentials: credentials))
        return try BilibiliAPI.decodePlayback(data, credentials: credentials)
    }
}

public enum BilibiliProviderFactory {
    public static func defaultProvider(credentials: BilibiliCredentials = .environment()) -> any BilibiliBangumiProviding {
        BilibiliBangumiProvider(credentials: credentials)
    }
}

public enum BilibiliAPI {
    public static func homeRequest(cursor: String = "0", credentials: BilibiliCredentials = .environment()) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/pgc/page/pc/bangumi/tab")!
            .appending(queryItems: [
                URLQueryItem(name: "mobi_app", value: "android"),
                URLQueryItem(name: "build", value: "8130300"),
                URLQueryItem(name: "is_refresh", value: "0"),
                URLQueryItem(name: "cursor", value: cursor)
            ])
        return request(url, credentials: credentials)
    }

    public static func searchBangumiRequest(
        keyword: String,
        page: Int = 1,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/search/type")!
            .appending(queryItems: [
                URLQueryItem(name: "search_type", value: "media_bangumi"),
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "\(max(page, 1))"),
                URLQueryItem(name: "order", value: "totalrank")
            ])
        return request(url, credentials: credentials)
    }

    public static func searchVideoRequest(
        keyword: String,
        page: Int = 1,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/search/type")!
            .appending(queryItems: [
                URLQueryItem(name: "search_type", value: "video"),
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "\(max(page, 1))"),
                URLQueryItem(name: "order", value: "totalrank")
            ])
        return request(url, credentials: credentials)
    }

    public static func popularVideoRequest(
        page: Int = 1,
        pageSize: Int = 20,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/x/web-interface/popular")!
            .appending(queryItems: [
                URLQueryItem(name: "pn", value: "\(max(page, 1))"),
                URLQueryItem(name: "ps", value: "\(max(min(pageSize, 50), 1))")
            ])
        return request(url, credentials: credentials)
    }

    public static func seasonDetailRequest(
        seasonID: Int,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        let url = URL(string: "https://api.bilibili.com/pgc/view/web/season")!
            .appending(queryItems: [URLQueryItem(name: "season_id", value: "\(seasonID)")])
        return request(url, credentials: credentials)
    }

    public static func videoDetailRequest(
        item: BilibiliSeason,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        var items: [URLQueryItem] = []
        if let bvid = item.bvid {
            items.append(URLQueryItem(name: "bvid", value: bvid))
        } else {
            items.append(URLQueryItem(name: "aid", value: "\(item.aid ?? item.id)"))
        }
        let url = URL(string: "https://api.bilibili.com/x/web-interface/view")!
            .appending(queryItems: items)
        return request(url, credentials: credentials)
    }

    public static func playURLRequest(
        episode: BilibiliEpisode,
        credentials: BilibiliCredentials = .environment()
    ) -> AnimeHTTPRequest {
        if let bvid = episode.bvid, let cid = episode.cid {
            let url = URL(string: "https://api.bilibili.com/x/player/playurl")!
                .appending(queryItems: [
                    URLQueryItem(name: "bvid", value: bvid),
                    URLQueryItem(name: "cid", value: "\(cid)"),
                    URLQueryItem(name: "qn", value: "80"),
                    URLQueryItem(name: "fnver", value: "0"),
                    URLQueryItem(name: "fnval", value: "0"),
                    URLQueryItem(name: "fourk", value: "1")
                ])
            return request(url, credentials: credentials)
        }
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
        return request(url, credentials: credentials)
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

    public static func decodeVideoSearch(_ data: Data) throws -> [BilibiliSeason] {
        let response = try JSONDecoder().decode(BilibiliVideoSearchResponse.self, from: data)
        try check(code: response.code, message: response.message)
        return uniqueItems(response.data?.result.compactMap(\.item) ?? [])
    }

    public static func decodePopularVideos(_ data: Data) throws -> [BilibiliSeason] {
        let response = try JSONDecoder().decode(BilibiliPopularVideoResponse.self, from: data)
        try check(code: response.code, message: response.message)
        return uniqueItems(response.data?.list.compactMap(\.item) ?? [])
    }

    public static func decodeSeasonDetail(_ data: Data) throws -> BilibiliSeasonDetail {
        let response = try JSONDecoder().decode(BilibiliSeasonDetailResponse.self, from: data)
        try check(code: response.code, message: response.message)
        guard let result = response.result else {
            throw BilibiliAPIError.missingData("season detail")
        }
        return result.detail
    }

    public static func decodeVideoDetail(_ data: Data) throws -> BilibiliSeasonDetail {
        let response = try JSONDecoder().decode(BilibiliVideoDetailResponse.self, from: data)
        try check(code: response.code, message: response.message)
        guard let data = response.data else {
            throw BilibiliAPIError.missingData("video detail")
        }
        return data.detail
    }

    public static func decodePlayback(
        _ data: Data,
        credentials: BilibiliCredentials = .environment()
    ) throws -> BilibiliPlaybackStream {
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
            headers: playbackHeaders(credentials: credentials),
            durationSeconds: result.duration.map { Double($0) / 1000 }
        )
    }

    private static func playbackHeaders(credentials: BilibiliCredentials = .environment()) -> [String: String] {
        [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15",
            "Referer": "https://www.bilibili.com/",
            "Origin": "https://www.bilibili.com"
        ].merging(credentials.requestHeaders, uniquingKeysWith: { _, new in new })
    }

    private static func request(_ url: URL, credentials: BilibiliCredentials = .environment()) -> AnimeHTTPRequest {
        AnimeHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/json,text/plain,*/*",
                "User-Agent": playbackHeaders()["User-Agent"] ?? "Mozilla/5.0",
                "Referer": "https://www.bilibili.com/",
                "Origin": "https://www.bilibili.com"
            ].merging(credentials.requestHeaders, uniquingKeysWith: { _, new in new })
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

    public static func uniqueItems(_ items: [BilibiliSeason]) -> [BilibiliSeason] {
        var seen = Set<String>()
        return items.filter { item in
            let key = item.bvid ?? "\(item.itemKind.rawValue):\(item.id)"
            return seen.insert(key).inserted
        }
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

private struct BilibiliVideoSearchResponse: Decodable {
    var code: Int
    var message: String?
    var data: BilibiliVideoSearchData?
}

private struct BilibiliVideoSearchData: Decodable {
    var result: [BilibiliVideoSearchItem]
}

private struct BilibiliVideoSearchItem: Decodable {
    var aid: Int?
    var bvid: String?
    var title: String?
    var pic: String?
    var author: String?
    var duration: String?
    var play: Int?
    var danmaku: Int?

    var item: BilibiliSeason? {
        guard let title = title?.cleanBilibiliHTML,
              title.isEmpty == false,
              let stableID = aid ?? bvid?.stableBilibiliID
        else {
            return nil
        }
        let subtitle = [
            author,
            duration,
            play.map { "\($0) 次觀看" },
            danmaku.map { "\($0) 彈幕" }
        ]
        .compactMap { $0?.cleanBilibiliHTML }
        .filter { $0.isEmpty == false }
        .joined(separator: " · ")
        return BilibiliSeason(
            id: stableID,
            itemKind: .video,
            aid: aid,
            bvid: bvid,
            title: title,
            subtitle: subtitle.isEmpty ? "一般影片" : subtitle,
            coverURL: pic.flatMap(BilibiliURL.normalizeImageURL),
            badge: "影片",
            totalText: duration
        )
    }
}

private struct BilibiliPopularVideoResponse: Decodable {
    var code: Int
    var message: String?
    var data: BilibiliPopularVideoData?
}

private struct BilibiliPopularVideoData: Decodable {
    var list: [BilibiliPopularVideoItem]
}

private struct BilibiliPopularVideoItem: Decodable {
    var aid: Int?
    var bvid: String?
    var title: String?
    var pic: String?
    var owner: BilibiliVideoOwner?
    var duration: Int?
    var stat: BilibiliStat?

    var item: BilibiliSeason? {
        guard let title = title?.cleanBilibiliHTML,
              title.isEmpty == false,
              let stableID = aid ?? bvid?.stableBilibiliID
        else {
            return nil
        }
        let subtitleParts: [String?] = [
            owner?.name,
            duration.map(BilibiliURL.durationLabel(seconds:)),
            (stat?.views ?? stat?.view).map { "\($0) 次觀看" },
            (stat?.danmakus ?? stat?.danmaku).map { "\($0) 彈幕" }
        ]
        let subtitle = subtitleParts
        .compactMap { $0?.cleanBilibiliHTML }
        .filter { $0.isEmpty == false }
        .joined(separator: " · ")
        return BilibiliSeason(
            id: stableID,
            itemKind: .video,
            aid: aid,
            bvid: bvid,
            title: title,
            subtitle: subtitle.isEmpty ? "一般影片" : subtitle,
            coverURL: pic.flatMap(BilibiliURL.normalizeImageURL),
            badge: "影片",
            totalText: duration.map(BilibiliURL.durationLabel(seconds:))
        )
    }
}

private struct BilibiliSeasonDetailResponse: Decodable {
    var code: Int
    var message: String?
    var result: BilibiliSeasonDetailPayload?
}

private struct BilibiliVideoDetailResponse: Decodable {
    var code: Int
    var message: String?
    var data: BilibiliVideoDetailPayload?
}

private struct BilibiliVideoDetailPayload: Decodable {
    var aid: Int?
    var bvid: String?
    var cid: Int?
    var title: String?
    var pic: String?
    var desc: String?
    var owner: BilibiliVideoOwner?
    var stat: BilibiliStat?
    var pages: [BilibiliVideoPage]?

    var detail: BilibiliSeasonDetail {
        let stableID = aid ?? bvid?.stableBilibiliID ?? cid ?? 0
        let parsedPages = (pages ?? []).enumerated().compactMap { offset, page in
            page.episode(
                defaultNumber: offset + 1,
                aid: aid,
                bvid: bvid,
                fallbackCID: cid,
                fallbackTitle: title
            )
        }
        let fallbackEpisode = BilibiliEpisode(
            id: cid ?? stableID,
            aid: aid,
            cid: cid,
            bvid: bvid,
            title: "播放",
            longTitle: title?.cleanBilibiliHTML ?? "Bilibili 影片",
            coverURL: pic.flatMap(BilibiliURL.normalizeImageURL),
            badge: "影片",
            number: 1
        )
        return BilibiliSeasonDetail(
            id: stableID,
            title: title?.cleanBilibiliHTML ?? "Bilibili 影片",
            coverURL: pic.flatMap(BilibiliURL.normalizeImageURL),
            subtitle: owner?.name?.cleanBilibiliHTML,
            evaluate: desc?.cleanBilibiliHTML,
            views: stat?.views ?? stat?.view,
            danmaku: stat?.danmakus ?? stat?.danmaku,
            episodes: parsedPages.isEmpty ? [fallbackEpisode] : parsedPages
        )
    }
}

private struct BilibiliVideoOwner: Decodable {
    var name: String?
}

private struct BilibiliVideoPage: Decodable {
    var cid: Int?
    var page: Int?
    var part: String?
    var duration: Int?

    func episode(
        defaultNumber: Int,
        aid: Int?,
        bvid: String?,
        fallbackCID: Int?,
        fallbackTitle: String?
    ) -> BilibiliEpisode? {
        let resolvedCID = cid ?? fallbackCID
        guard let resolvedCID else {
            return nil
        }
        let number = page ?? defaultNumber
        let title = part?.cleanBilibiliHTML ?? fallbackTitle?.cleanBilibiliHTML ?? "P\(number)"
        return BilibiliEpisode(
            id: resolvedCID,
            aid: aid,
            cid: resolvedCID,
            bvid: bvid,
            title: "P\(number)",
            longTitle: title,
            badge: duration.map { BilibiliURL.durationLabel(seconds: $0) },
            number: number
        )
    }
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

    var stableBilibiliID: Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(Int.max))
    }
}

private enum BilibiliURL {
    static func normalizeImageURL(_ rawValue: String) -> URL? {
        if rawValue.hasPrefix("//") {
            return URL(string: "https:\(rawValue)")
        }
        return URL(string: rawValue)
    }

    static func durationLabel(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
