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
        let results = items.compactMap { item -> AnimeSearchResult? in
            guard let streamURL = item.streamURL else {
                return nil
            }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.isEmpty == false else {
                return nil
            }
            let episodeNumber = episodeNumber(from: title)
            let episode = AnimeEpisode(
                id: "\(id)-\(stableID(title))-episode-\(episodeNumber)",
                title: title,
                number: episodeNumber,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: title,
                    episodeID: streamURL.absoluteString
                )
            )
            return AnimeSearchResult(
                id: "\(id)-\(stableID(title))",
                title: title,
                subtitle: "\(displayName) · BT/RSS",
                episodeCount: 1,
                episodes: [episode]
            )
        }
        return Array(results.prefix(30))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let url = URL(string: episode.identity.episodeID) else {
            throw AnimeHTTPError.missingRoute("torrent stream url: \(episode.identity.episodeID)")
        }
        return [
            AnimeStreamCandidate(
                url: url,
                quality: "BT / RSS",
                priority: 55,
                headers: ["resolver": "torrent", "source": displayName]
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

    private func episodeNumber(from title: String) -> Int {
        let patterns = [
            #"第\s*([0-9]+)\s*[話话集]"#,
            #"\[([0-9]{1,3})\]"#,
            #"EP\s*([0-9]+)"#,
            #"Episode\s*([0-9]+)"#
        ]
        for pattern in patterns {
            if let number = firstCapture(in: title, pattern: pattern).flatMap(Int.init) {
                return number
            }
        }
        return 1
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
