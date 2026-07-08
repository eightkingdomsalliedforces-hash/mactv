import Foundation

public enum SelectorCaptchaKind: String, Codable, Equatable, Sendable {
    case image
    case cloudflare
    case unknown
}

public enum SelectorAnimeSourceError: Error, Equatable, LocalizedError, Sendable {
    case invalidSearchURL
    case invalidRegex(String)
    case captchaRequired(SelectorCaptchaKind)
    case noMatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSearchURL:
            "Selector 來源搜尋網址無效。"
        case let .invalidRegex(pattern):
            "Selector 規則無法編譯：\(pattern)"
        case let .captchaRequired(kind):
            "來源需要互動驗證：\(kind.rawValue)"
        case let .noMatch(label):
            "Selector 沒有解析到內容：\(label)"
        }
    }
}

public struct SelectorMatchPattern: Codable, Equatable, Sendable {
    public var pattern: String
    public var idGroup: Int
    public var urlGroup: Int
    public var titleGroup: Int

    public init(pattern: String, idGroup: Int, urlGroup: Int, titleGroup: Int) {
        self.pattern = pattern
        self.idGroup = idGroup
        self.urlGroup = urlGroup
        self.titleGroup = titleGroup
    }
}

public struct SelectorStreamPattern: Codable, Equatable, Sendable {
    public var pattern: String
    public var urlGroup: Int
    public var qualityGroup: Int?

    public init(pattern: String, urlGroup: Int, qualityGroup: Int? = nil) {
        self.pattern = pattern
        self.urlGroup = urlGroup
        self.qualityGroup = qualityGroup
    }
}

public struct SelectorAnimeSourceConfig: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var searchURLTemplate: String
    public var resultPattern: SelectorMatchPattern
    public var episodePattern: SelectorMatchPattern
    public var streamPattern: SelectorStreamPattern
    public var userAgent: String

    public init(
        id: String,
        displayName: String,
        searchURLTemplate: String,
        resultPattern: SelectorMatchPattern,
        episodePattern: SelectorMatchPattern,
        streamPattern: SelectorStreamPattern,
        userAgent: String = "TVShell/0.1 SelectorAnimeSource"
    ) {
        self.id = id
        self.displayName = displayName
        self.searchURLTemplate = searchURLTemplate
        self.resultPattern = resultPattern
        self.episodePattern = episodePattern
        self.streamPattern = streamPattern
        self.userAgent = userAgent
    }

    public static func environment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [SelectorAnimeSourceConfig] {
        guard let rawValue = environment["TVSHELL_SELECTOR_SOURCES_JSON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false
        else {
            return []
        }
        return try JSONDecoder().decode([SelectorAnimeSourceConfig].self, from: Data(rawValue.utf8))
    }

    public var catalogDefinition: AnimeSourceDefinition {
        AnimeSourceDefinition(
            id: id,
            title: displayName,
            iconLabel: "S",
            lines: [AnimeSourceLine(id: "\(id)-selector", title: "Selector")],
            health: .available,
            defaultEnabled: true
        )
    }
}

public struct SelectorAnimeSourceProvider: AnimeMediaSourceAdapter {
    public let id: String
    public let displayName: String
    public let resolverKind: AnimeResolverKind = .http

    private let config: SelectorAnimeSourceConfig
    private let transport: any AnimeHTTPTransport

    public init(config: SelectorAnimeSourceConfig, transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()) {
        self.config = config
        self.transport = transport
        id = config.id
        displayName = config.displayName
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let searchURL = try buildSearchURL(keyword: query.keyword)
        let searchHTML = try await html(for: searchURL)
        let resultMatches = try SelectorPatternEngine.matches(pattern: config.resultPattern.pattern, in: searchHTML)
        let baseURL = searchURL

        var results: [AnimeSearchResult] = []
        for match in resultMatches {
            guard let id = match.group(config.resultPattern.idGroup),
                  let title = match.group(config.resultPattern.titleGroup),
                  let rawURL = match.group(config.resultPattern.urlGroup),
                  let detailURL = URL.tvShellResolved(rawURL, relativeTo: baseURL)
            else {
                continue
            }

            let detailHTML = try await html(for: detailURL)
            let episodes = try parseEpisodes(html: detailHTML, subjectID: title, baseURL: detailURL)
            results.append(AnimeSearchResult(id: id, title: title, subtitle: displayName, episodes: episodes))
        }

        if results.isEmpty {
            throw SelectorAnimeSourceError.noMatch("search results")
        }
        return results
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let pageURL = episode.identity.playbackURL ?? URL(string: episode.identity.episodeID) else {
            throw SelectorAnimeSourceError.noMatch("episode url")
        }

        let watchHTML = try await html(for: pageURL)
        let streamMatches = try SelectorPatternEngine.matches(pattern: config.streamPattern.pattern, in: watchHTML)
        let streams = streamMatches.compactMap { match -> AnimeStreamCandidate? in
            guard let rawURL = match.group(config.streamPattern.urlGroup),
                  let streamURL = URL.tvShellResolved(rawURL, relativeTo: pageURL)
            else {
                return nil
            }
            return AnimeStreamCandidate(
                url: streamURL,
                quality: config.streamPattern.qualityGroup.flatMap(match.group) ?? "自動",
                priority: 70,
                headers: ["User-Agent": config.userAgent]
            )
        }

        if streams.isEmpty {
            throw SelectorAnimeSourceError.noMatch("streams")
        }
        return streams
    }

    private func buildSearchURL(keyword: String) throws -> URL {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let value = config.searchURLTemplate.replacingOccurrences(of: "{keyword}", with: encodedKeyword)
        guard let url = URL(string: value) else {
            throw SelectorAnimeSourceError.invalidSearchURL
        }
        return url
    }

    private func html(for url: URL) async throws -> String {
        let data = try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "text/html,application/xhtml+xml",
                "User-Agent": config.userAgent
            ]
        ))
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if let captcha = SelectorCaptchaDetector.detect(url: url, html: html) {
            throw SelectorAnimeSourceError.captchaRequired(captcha)
        }
        return html
    }

    private func parseEpisodes(html: String, subjectID: String, baseURL: URL) throws -> [AnimeEpisode] {
        let matches = try SelectorPatternEngine.matches(pattern: config.episodePattern.pattern, in: html)
        let episodes: [AnimeEpisode] = matches.compactMap { match in
            guard let rawNumber = match.group(config.episodePattern.idGroup),
                  let title = match.group(config.episodePattern.titleGroup),
                  let rawURL = match.group(config.episodePattern.urlGroup),
                  let episodeURL = URL.tvShellResolved(rawURL, relativeTo: baseURL)
            else {
                return nil
            }

            let number = Int(rawNumber.filter(\.isNumber)) ?? 0
            return AnimeEpisode(
                id: "\(id)-\(subjectID)-\(rawNumber)",
                title: title,
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: subjectID,
                    episodeID: rawNumber,
                    playbackURL: episodeURL
                )
            )
        }

        if episodes.isEmpty {
            throw SelectorAnimeSourceError.noMatch("episodes")
        }
        return episodes.sorted { $0.number < $1.number }
    }
}

private struct SelectorPatternEngine {
    static func matches(pattern: String, in html: String) throws -> [SelectorRegexMatch] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        } catch {
            throw SelectorAnimeSourceError.invalidRegex(pattern)
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).map { result in
            SelectorRegexMatch(text: html, result: result)
        }
    }
}

private struct SelectorRegexMatch {
    let text: String
    let result: NSTextCheckingResult

    func group(_ index: Int) -> String? {
        guard index < result.numberOfRanges else {
            return nil
        }
        let range = result.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text)
        else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SelectorCaptchaDetector {
    static func detect(url: URL, html: String) -> SelectorCaptchaKind? {
        let lowerHTML = html.lowercased()
        let lowerURL = url.absoluteString.lowercased()

        if lowerHTML.contains("cf-turnstile")
            || lowerHTML.contains("turnstile.render")
            || lowerHTML.contains("window._cf_chl_opt")
            || lowerHTML.contains("__cf_chl_")
            || lowerURL.contains("__cf_chl_")
            || lowerURL.contains("/cdn-cgi/challenge-platform/")
            || (lowerHTML.contains("<title>just a moment") && lowerHTML.contains("cf")) {
            return .cloudflare
        }

        if (lowerHTML.contains("captcha") || lowerHTML.contains("驗證碼") || lowerHTML.contains("验证码"))
            && (lowerHTML.contains("<img") || lowerHTML.contains("verify")) {
            return .image
        }

        return nil
    }
}

private extension URL {
    static func tvShellResolved(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}
