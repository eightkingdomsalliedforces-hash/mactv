import Foundation

public struct BTFeedAnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id: String
    public let displayName: String
    public let resolverKind: AnimeResolverKind = .torrent

    private let searchURLTemplate: String
    private let transport: any AnimeHTTPTransport

    public init(
        id: String,
        displayName: String,
        searchURLTemplate: String,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.id = id
        self.displayName = displayName
        self.searchURLTemplate = searchURLTemplate
        self.transport = transport
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let url = try searchURL(keyword: query.keyword)
        let data = try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/rss+xml, application/xml, text/xml",
                "User-Agent": "TVShell/0.1 BTFeedAnimeSource"
            ]
        ))
        let items = try BTFeedParser.parse(data)
        let metadata = await bangumiMetadata(keyword: query.keyword)
        let releases = items.flatMap { item -> [BTFeedRelease] in
            guard let streamURL = item.streamURL else {
                return []
            }
            let rawTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard rawTitle.isEmpty == false else {
                return []
            }
            let displayTitle = metadata.title ?? cleanTitle(rawTitle)
            let episodeNumbers = episodeNumbers(from: rawTitle)
            let quality = qualityLabel(from: rawTitle)
            return episodeNumbers.map { episodeNumber in
                let episode = AnimeEpisode(
                    id: "\(id)-\(stableID(rawTitle))-episode-\(episodeNumber)",
                    title: "第 \(episodeNumber) 話 · \(quality)",
                    number: episodeNumber,
                    identity: AnimeEpisodeIdentity(
                        providerID: id,
                        subjectID: displayTitle,
                        episodeID: "\(episodeNumber)",
                        playbackURL: streamURL
                    )
                )
                return BTFeedRelease(title: displayTitle, rawTitle: rawTitle, episode: episode)
            }
        }

        var grouped: [String: [BTFeedRelease]] = [:]
        for release in releases {
            grouped[release.title, default: []].append(release)
        }

        let results = grouped
            .map { title, releases in
                var seenEpisodeNumbers = Set<Int>()
                let sortedEpisodes = releases
                    .map(\.episode)
                    .sorted { left, right in
                        if left.number == right.number {
                            return left.title < right.title
                        }
                        return left.number < right.number
                    }
                    .filter { episode in
                        if seenEpisodeNumbers.contains(episode.number) {
                            return false
                        }
                        seenEpisodeNumbers.insert(episode.number)
                        return true
                    }
                let rawSubtitle = releases.first?.rawTitle ?? "\(displayName) · BT/RSS"
                return AnimeSearchResult(
                    id: "\(id)-\(stableID(title))",
                    title: title,
                    subtitle: "\(displayName) · \(rawSubtitle)",
                    coverURL: metadata.coverURL,
                    episodeCount: sortedEpisodes.count,
                    episodes: sortedEpisodes
                )
            }
            .sorted { left, right in
                if left.title == right.title {
                    return (left.episodeCount ?? 0) > (right.episodeCount ?? 0)
                }
                return left.title < right.title
            }

        return Array(results.prefix(30))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let url = episode.identity.playbackURL ?? URL(string: episode.identity.episodeID) else {
            throw AnimeHTTPError.missingRoute("torrent stream url: \(episode.identity.episodeID)")
        }
        return [
            AnimeStreamCandidate(
                url: url,
                quality: "BT / RSS",
                priority: 55,
                headers: [
                    "resolver": "torrent",
                    "source": displayName,
                    "title": episode.identity.subjectID,
                    "episode": episode.title
                ]
            )
        ]
    }

    private func searchURL(keyword: String) throws -> URL {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let value = searchURLTemplate.replacingOccurrences(of: "{keyword}", with: encoded)
        guard let url = URL(string: value) else {
            throw AnimeHTTPError.missingRoute(value)
        }
        return url
    }

    private func episodeNumbers(from title: String) -> [Int] {
        let rangePatterns = [
            #"\[([0-9]{1,3})\s*[-~～]\s*([0-9]{1,3})\]"#,
            #"第\s*([0-9]{1,3})\s*[-~～]\s*([0-9]{1,3})\s*[話话集]"#,
            #"-\s*(0[0-9]{1,2})\s*[-~～]\s*([0-9]{1,3})(?=\s|\[|\]|$)"#
        ]
        for pattern in rangePatterns {
            if let range = firstTwoCaptures(in: title, pattern: pattern),
               range.0 > 0,
               range.1 >= range.0,
               range.1 - range.0 <= 80 {
                return Array(range.0...range.1)
            }
        }

        let patterns = [
            #"第\s*([0-9]+)\s*[話话集]"#,
            #"-\s*([0-9]{1,3})\s*(?:END|完|\[|$)"#,
            #"\[([0-9]{1,3})\]"#,
            #"EP\s*([0-9]+)"#,
            #"Episode\s*([0-9]+)"#
        ]
        for pattern in patterns {
            if let number = firstCapture(in: title, pattern: pattern).flatMap(Int.init) {
                return [number]
            }
        }
        return [1]
    }

    private func firstTwoCaptures(in value: String, pattern: String) -> (Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 2,
              let firstRange = Range(match.range(at: 1), in: value),
              let secondRange = Range(match.range(at: 2), in: value),
              let first = Int(value[firstRange]),
              let second = Int(value[secondRange])
        else {
            return nil
        }
        return (first, second)
    }

    private func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[swiftRange])
    }

    private func qualityLabel(from title: String) -> String {
        let lowercased = title.lowercased()
        if lowercased.contains("2160") || lowercased.contains("4k") {
            return "4K"
        }
        if lowercased.contains("1080") {
            return "1080p"
        }
        if lowercased.contains("720") {
            return "720p"
        }
        return "BT"
    }

    private func bangumiMetadata(keyword: String) async -> (title: String?, coverURL: URL?) {
        do {
            let request = try BangumiAPI.searchSubjectsRequest(keyword: keyword)
            let data = try await transport.data(for: request)
            guard let subject = try BangumiAPI.decodeSubjectSearch(data).first else {
                return (nil, nil)
            }
            return (subject.title, subject.coverURL)
        } catch {
            return (nil, nil)
        }
    }

    private func cleanTitle(_ value: String) -> String {
        var title = value
        title = title.replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\([^\)]+\)"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"(?<![0-9])[0-9]{1,3}\s*[-~～]\s*[0-9]{1,3}(?![0-9])"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"第\s*[0-9]+\s*[話话集]"#, with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: #"-\s*[0-9]{1,3}\s*(?:END|完)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"EP\s*[0-9]+"#, with: " ", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"Episode\s*[0-9]+"#, with: " ", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"[0-9]{3,4}p|x264|x265|hevc|avc|繁中|簡中|简中|外挂|內封|内封|BIG5|GB|CHT|CHS"#, with: " ", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stableID(_ value: String) -> String {
        value.unicodeScalars
            .map { String(format: "%02X", $0.value) }
            .joined()
            .prefix(80)
            .description
    }
}

public struct MediaServerAnimeSourceConfig: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case jellyfin
        case emby
    }

    public var id: String
    public var displayName: String
    public var kind: Kind
    public var baseURL: URL
    public var apiKey: String
    public var userID: String?

    public init(id: String, displayName: String, kind: Kind, baseURL: URL, apiKey: String, userID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.userID = userID
    }

    public static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> [MediaServerAnimeSourceConfig] {
        var configs: [MediaServerAnimeSourceConfig] = []
        if let jellyfin = config(
            id: "jellyfin",
            displayName: "Jellyfin",
            kind: .jellyfin,
            prefix: "TVSHELL_JELLYFIN",
            environment: environment
        ) {
            configs.append(jellyfin)
        }
        if let emby = config(
            id: "emby",
            displayName: "Emby",
            kind: .emby,
            prefix: "TVSHELL_EMBY",
            environment: environment
        ) {
            configs.append(emby)
        }
        return configs
    }

    public var catalogDefinition: AnimeSourceDefinition {
        AnimeSourceDefinition(
            id: id,
            title: displayName,
            iconLabel: kind == .jellyfin ? "JF" : "E",
            lines: [AnimeSourceLine(id: "\(id)-server", title: "自有媒體庫")],
            health: .available,
            defaultEnabled: true
        )
    }

    private static func config(
        id: String,
        displayName: String,
        kind: Kind,
        prefix: String,
        environment: [String: String]
    ) -> MediaServerAnimeSourceConfig? {
        guard let rawBaseURL = environment["\(prefix)_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let baseURL = URL(string: rawBaseURL),
              let apiKey = environment["\(prefix)_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              apiKey.isEmpty == false
        else {
            return nil
        }
        let userID = environment["\(prefix)_USER_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaServerAnimeSourceConfig(
            id: id,
            displayName: displayName,
            kind: kind,
            baseURL: baseURL,
            apiKey: apiKey,
            userID: userID?.isEmpty == false ? userID : nil
        )
    }
}

public struct MediaServerAnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id: String
    public let displayName: String
    public let resolverKind: AnimeResolverKind = .http

    private let config: MediaServerAnimeSourceConfig
    private let transport: any AnimeHTTPTransport

    public init(config: MediaServerAnimeSourceConfig, transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()) {
        self.config = config
        self.transport = transport
        id = config.id
        displayName = config.displayName
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let data = try await transport.data(for: request(path: "/Items", queryItems: [
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: "Series"),
            URLQueryItem(name: "SearchTerm", value: query.keyword),
            URLQueryItem(name: "Fields", value: "Overview,ProductionYear")
        ]))
        let response = try JSONDecoder().decode(MediaServerItemsResponse.self, from: data)
        return response.items.map { item in
            AnimeSearchResult(
                id: "\(id)-\(item.id)",
                title: item.name,
                subtitle: item.overview,
                coverURL: imageURL(itemID: item.id),
                airDate: item.productionYear.map(String.init),
                episodes: [
                    AnimeEpisode(
                        id: "\(id)-\(item.id)-placeholder",
                        title: "載入選集",
                        number: 1,
                        identity: AnimeEpisodeIdentity(providerID: id, subjectID: item.id, episodeID: item.id)
                    )
                ]
            )
        }
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        let seriesID = result.id.replacingOccurrences(of: "\(id)-", with: "")
        let data = try await transport.data(for: request(path: "/Shows/\(seriesID)/Episodes", queryItems: [
            URLQueryItem(name: "Fields", value: "Overview,ParentIndexNumber,IndexNumber")
        ]))
        let response = try JSONDecoder().decode(MediaServerItemsResponse.self, from: data)
        return response.items.enumerated().map { index, item in
            let number = item.indexNumber ?? index + 1
            return AnimeEpisode(
                id: "\(id)-\(item.id)",
                title: item.name,
                number: number,
                identity: AnimeEpisodeIdentity(providerID: id, subjectID: seriesID, episodeID: item.id)
            )
        }
        .sorted { $0.number < $1.number }
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        let streamURL = try url(path: "/Videos/\(episode.identity.episodeID)/stream.mp4", queryItems: [
            URLQueryItem(name: "Static", value: "true")
        ])
        return [
            AnimeStreamCandidate(
                url: streamURL,
                quality: "\(displayName) 直連",
                priority: 95,
                headers: ["X-Emby-Token": config.apiKey]
            )
        ]
    }

    private func request(path: String, queryItems: [URLQueryItem]) throws -> AnimeHTTPRequest {
        AnimeHTTPRequest(
            method: "GET",
            url: try url(path: path, queryItems: queryItems),
            headers: [
                "Accept": "application/json",
                "X-Emby-Token": config.apiKey,
                "User-Agent": "TVShell/0.1 \(displayName)"
            ]
        )
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: config.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: config.apiKey))
        if let userID = config.userID {
            items.append(URLQueryItem(name: "UserId", value: userID))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw AnimeHTTPError.missingRoute(path)
        }
        return url
    }

    private func imageURL(itemID: String) -> URL? {
        try? url(path: "/Items/\(itemID)/Images/Primary", queryItems: [])
    }
}

private struct MediaServerItemsResponse: Decodable {
    var items: [MediaServerItem]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

private struct MediaServerItem: Decodable {
    var id: String
    var name: String
    var overview: String?
    var productionYear: Int?
    var indexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case indexNumber = "IndexNumber"
    }
}

private struct BTFeedItem {
    var title = ""
    var link: URL?
    var enclosureURL: URL?
    var magnetURL: URL?

    var streamURL: URL? {
        magnetURL ?? enclosureURL ?? link
    }
}

private struct BTFeedRelease {
    var title: String
    var rawTitle: String
    var episode: AnimeEpisode
}

private final class BTFeedParser: NSObject, XMLParserDelegate {
    private var items: [BTFeedItem] = []
    private var currentItem: BTFeedItem?
    private var currentElement = ""
    private var text = ""

    static func parse(_ data: Data) throws -> [BTFeedItem] {
        let delegate = BTFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? AnimeHTTPError.missingRoute("rss parse")
        }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        text = ""
        if currentElement == "item" {
            currentItem = BTFeedItem()
        }
        if currentElement == "enclosure",
           let rawURL = attributeDict["url"],
           let url = URL(string: rawURL) {
            currentItem?.enclosureURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "title" {
            currentItem?.title = value
        } else if name == "link" {
            if value.hasPrefix("magnet:") {
                currentItem?.magnetURL = URL(string: value)
            } else if let url = URL(string: value) {
                currentItem?.link = url
            }
        } else if name == "magnet" || name == "magneturi" {
            currentItem?.magnetURL = URL(string: value)
        } else if name == "item", let item = currentItem {
            items.append(item)
            currentItem = nil
        }
        text = ""
    }
}
