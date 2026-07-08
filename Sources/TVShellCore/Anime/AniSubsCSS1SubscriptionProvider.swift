import Foundation

public struct AniSubsCSS1SubscriptionProvider: AnimeMediaSourceAdapter {
    public let id = "ani-subs-css1"
    public let displayName = "ani-subs CSS1"
    public let resolverKind: AnimeResolverKind = .http

    private let subscriptionURL: URL
    private let transport: any AnimeHTTPTransport

    public init(
        subscriptionURL: URL = URL(string: "https://sub.creamycake.org/v1/css1.json")!,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.subscriptionURL = subscriptionURL
        self.transport = transport
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let sources = try await webSelectorSources()
        var allResults: [AnimeSearchResult] = []

        for source in sources {
            do {
                let searchURL = try source.searchURL(keyword: query.keyword)
                let searchHTML = try await html(for: searchURL, userAgent: source.userAgent)
                let subjects = CSS1HTMLSelectorEngine.anchors(
                    matching: source.searchSelector,
                    in: searchHTML,
                    baseURL: searchURL
                )

                for subject in subjects.prefix(20) {
                    let detailHTML = try await html(for: subject.url, userAgent: source.userAgent)
                    let episodes = parseEpisodes(
                        source: source,
                        subjectTitle: subject.title,
                        detailHTML: detailHTML,
                        detailURL: subject.url
                    )
                    guard episodes.isEmpty == false else {
                        continue
                    }
                    allResults.append(AnimeSearchResult(
                        id: "\(id)-\(stableID(source.name))-\(stableID(subject.url.absoluteString))",
                        title: subject.title,
                        subtitle: source.name,
                        episodeCount: episodes.count,
                        episodes: episodes
                    ))
                }
            } catch {
                continue
            }
        }

        return Array(mergeCSS1Results(allResults).prefix(60))
    }

    public func episodes(for result: AnimeSearchResult) async throws -> [AnimeEpisode] {
        result.episodes.sorted { lhs, rhs in
            if lhs.number == rhs.number {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.number < rhs.number
        }
    }

    public func streams(for episode: AnimeEpisode) async throws -> [AnimeStreamCandidate] {
        guard let watchURL = episode.identity.playbackURL else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 playback url: \(episode.identity.episodeID)")
        }
        let source = try await source(named: episode.identity.providerID)
        let watchHTML = try await html(for: watchURL, userAgent: source.userAgent)
        guard let streamURL = CSS1HTMLSelectorEngine.firstVideoURL(
            in: watchHTML,
            pattern: source.videoPattern,
            baseURL: watchURL
        ) else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 video url: \(watchURL.absoluteString)")
        }

        return [
            AnimeStreamCandidate(
                url: streamURL,
                quality: "CSS1",
                priority: 64,
                headers: [
                    "resolver": "web-selector",
                    "source": source.name,
                    "title": episode.identity.subjectID,
                    "episode": episode.title,
                    "User-Agent": source.userAgent
                ]
            )
        ]
    }

    private func source(named name: String) async throws -> AniSubsCSS1Source {
        let sources = try await webSelectorSources()
        guard let source = sources.first(where: { $0.name == name }) ?? sources.first else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 source")
        }
        return source
    }

    private func webSelectorSources() async throws -> [AniSubsCSS1Source] {
        let data = try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: subscriptionURL,
            headers: [
                "Accept": "application/json",
                "User-Agent": "TVShell/0.1 ani-subs-css1"
            ]
        ))
        return try AniSubsCSS1Subscription.decode(data)
    }

    private func html(for url: URL, userAgent: String) async throws -> String {
        let data = try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "text/html,application/xhtml+xml",
                "User-Agent": userAgent
            ]
        ))
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if let captcha = CSS1HTMLSelectorEngine.detectCaptcha(url: url, html: html) {
            throw SelectorAnimeSourceError.captchaRequired(captcha)
        }
        return html
    }

    private func parseEpisodes(
        source: AniSubsCSS1Source,
        subjectTitle: String,
        detailHTML: String,
        detailURL: URL
    ) -> [AnimeEpisode] {
        let episodeHTML = CSS1HTMLSelectorEngine.blocks(matching: source.episodeListSelector, in: detailHTML)
            .joined(separator: "\n")
        let targetHTML = episodeHTML.isEmpty ? detailHTML : episodeHTML
        let anchors = CSS1HTMLSelectorEngine.anchors(
            matching: source.episodeSelector,
            in: targetHTML,
            baseURL: detailURL
        )

        return anchors.enumerated().map { offset, anchor in
            let number = CSS1HTMLSelectorEngine.episodeNumber(
                from: anchor.title,
                pattern: source.episodeSortPattern
            ) ?? offset + 1
            return AnimeEpisode(
                id: "\(id)-\(stableID(source.name))-\(stableID(anchor.url.absoluteString))",
                title: anchor.title,
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: source.name,
                    subjectID: subjectTitle,
                    episodeID: anchor.url.absoluteString,
                    subjectAliases: [subjectTitle],
                    playbackURL: anchor.url
                )
            )
        }
    }

    private func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

public struct AniSubsCSS1Source: Equatable, Sendable {
    public var name: String
    public var searchURLTemplate: String
    public var searchSelector: String
    public var episodeListSelector: String
    public var episodeSelector: String
    public var episodeSortPattern: String?
    public var videoPattern: String
    public var userAgent: String

    func searchURL(keyword: String) throws -> URL {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let value = searchURLTemplate.replacingOccurrences(of: "{keyword}", with: encodedKeyword)
        guard let url = URL(string: value) else {
            throw SelectorAnimeSourceError.invalidSearchURL
        }
        return url
    }
}

private enum AniSubsCSS1Subscription {
    static func decode(_ data: Data) throws -> [AniSubsCSS1Source] {
        let response = try JSONDecoder().decode(AniSubsCSS1Response.self, from: data)
        return response.exportedMediaSourceDataList.mediaSources.compactMap { source in
            guard source.factoryId == "web-selector",
                  let name = source.arguments.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  name.isEmpty == false,
                  let searchConfig = source.arguments.searchConfig,
                  searchConfig.searchUrl.contains("{keyword}"),
                  let searchSelector = searchConfig.selectorSubjectFormatA?.selectLists
                    ?? searchConfig.selectorSubjectFormatIndexed?.selectLists,
                  let episodeListSelector = searchConfig.selectorChannelFormatFlattened?.selectEpisodeLists,
                  let episodeSelector = searchConfig.selectorChannelFormatFlattened?.selectEpisodesFromList,
                  let videoPattern = searchConfig.matchVideo?.matchVideoUrl
            else {
                return nil
            }
            return AniSubsCSS1Source(
                name: name,
                searchURLTemplate: searchConfig.searchUrl,
                searchSelector: searchSelector,
                episodeListSelector: episodeListSelector,
                episodeSelector: episodeSelector,
                episodeSortPattern: searchConfig.selectorChannelFormatFlattened?.matchEpisodeSortFromName,
                videoPattern: videoPattern,
                userAgent: source.arguments.userAgent ?? "TVShell/0.1 ani-subs-css1"
            )
        }
    }
}

private struct AniSubsCSS1Response: Decodable {
    var exportedMediaSourceDataList: AniSubsCSS1MediaSourceList
}

private struct AniSubsCSS1MediaSourceList: Decodable {
    var mediaSources: [AniSubsCSS1MediaSource]
}

private struct AniSubsCSS1MediaSource: Decodable {
    var factoryId: String
    var arguments: AniSubsCSS1Arguments
}

private struct AniSubsCSS1Arguments: Decodable {
    var name: String?
    var searchConfig: AniSubsCSS1SearchConfig?
    var userAgent: String?
}

private struct AniSubsCSS1SearchConfig: Decodable {
    var searchUrl: String
    var selectorSubjectFormatA: AniSubsCSS1SubjectSelector?
    var selectorSubjectFormatIndexed: AniSubsCSS1SubjectSelector?
    var selectorChannelFormatFlattened: AniSubsCSS1EpisodeSelector?
    var matchVideo: AniSubsCSS1VideoMatcher?
}

private struct AniSubsCSS1SubjectSelector: Decodable {
    var selectLists: String?
}

private struct AniSubsCSS1EpisodeSelector: Decodable {
    var selectEpisodeLists: String?
    var selectEpisodesFromList: String?
    var matchEpisodeSortFromName: String?
}

private struct AniSubsCSS1VideoMatcher: Decodable {
    var matchVideoUrl: String?
}

private enum CSS1HTMLSelectorEngine {
    struct Anchor: Equatable {
        var title: String
        var url: URL
    }

    static func anchors(matching selector: String, in html: String, baseURL: URL) -> [Anchor] {
        let requiredClasses = classNames(in: selector)
        let anchorRegex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return anchorRegex?.matches(in: html, range: nsRange).compactMap { match in
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html)
            else {
                return nil
            }
            let prefixStart = html.index(html.startIndex, offsetBy: max(0, match.range.location - 1800))
            let prefix = String(html[prefixStart..<tagRange.lowerBound])
            if requiredClasses.isEmpty == false,
               requiredClasses.allSatisfy({ prefix.contains($0) || String(html[tagRange]).contains($0) }) == false {
                return nil
            }
            guard let href = attribute("href", in: String(html[tagRange])),
                  let url = resolveURL(href, relativeTo: baseURL)
            else {
                return nil
            }
            let title = normalize(stripHTML(String(html[textRange])))
            guard title.isEmpty == false else {
                return nil
            }
            return Anchor(title: title, url: url)
        } ?? []
    }

    static func blocks(matching selector: String, in html: String) -> [String] {
        let classes = classNames(in: selector)
        guard let firstClass = classes.first else {
            return []
        }
        let pattern = #"<(?<tag>[a-zA-Z0-9]+)\b[^>]*class\s*=\s*["'][^"']*"# + NSRegularExpression.escapedPattern(for: firstClass) + #"[^"']*["'][^>]*>(?<body>.*?)</\k<tag>>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard let range = Range(match.range(withName: "body"), in: html) else {
                return nil
            }
            return String(html[range])
        }
    }

    static func firstVideoURL(in html: String, pattern: String, baseURL: URL) -> URL? {
        let normalizedHTML = html
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u002F"#, with: "/")
        if let regex = try? NSRegularExpression(pattern: pattern.replacingOccurrences(of: #"\\/"#, with: "/"), options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let nsRange = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
            for match in regex.matches(in: normalizedHTML, range: nsRange) {
                for group in 1..<match.numberOfRanges {
                    guard let range = Range(match.range(at: group), in: normalizedHTML) else {
                        continue
                    }
                    let candidate = cleanURLCandidate(String(normalizedHTML[range]))
                    if candidate.hasPrefix("http"),
                       let url = resolveURL(candidate, relativeTo: baseURL) {
                        return url
                    }
                }
            }
        }

        let fallbackPattern = #"https?://[^"'\s<>\\]+?\.(?:mp4|m3u8|flv|mkv)(?:\?[^"'\s<>\\]+)?"#
        guard let fallback = try? NSRegularExpression(pattern: fallbackPattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
        guard let match = fallback.firstMatch(in: normalizedHTML, range: nsRange),
              let range = Range(match.range, in: normalizedHTML)
        else {
            return nil
        }
        return resolveURL(cleanURLCandidate(String(normalizedHTML[range])), relativeTo: baseURL)
    }

    static func episodeNumber(from title: String, pattern: String?) -> Int? {
        if let pattern,
           let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(title.startIndex..<title.endIndex, in: title)
            if let match = regex.firstMatch(in: title, range: nsRange) {
                for group in 1..<match.numberOfRanges {
                    guard let range = Range(match.range(at: group), in: title) else {
                        continue
                    }
                    let digits = String(title[range]).filter(\.isNumber)
                    if let value = Int(digits) {
                        return value
                    }
                }
            }
        }
        let digits = title.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    static func detectCaptcha(url: URL, html: String) -> SelectorCaptchaKind? {
        let lowercase = html.lowercased()
        if lowercase.contains("cf-challenge") || lowercase.contains("cloudflare") || lowercase.contains("turnstile") {
            return .cloudflare
        }
        if lowercase.contains("captcha") || lowercase.contains("驗證碼") || lowercase.contains("验证码") {
            return .image
        }
        if url.host?.localizedCaseInsensitiveContains("cloudflare") == true {
            return .cloudflare
        }
        return nil
    }

    private static func classNames(in selector: String) -> [String] {
        (try? NSRegularExpression(pattern: #"\.([A-Za-z0-9_-]+)"#))?
            .matches(in: selector, range: NSRange(selector.startIndex..<selector.endIndex, in: selector))
            .compactMap { match in
                guard let range = Range(match.range(at: 1), in: selector) else {
                    return nil
                }
                return String(selector[range])
            } ?? []
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
              let range = Range(match.range(at: 1), in: tag)
        else {
            return nil
        }
        return String(tag[range])
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanURLCandidate(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: #" "';)"#).union(.whitespacesAndNewlines))
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func resolveURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}

private func mergeCSS1Results(_ results: [AnimeSearchResult]) -> [AnimeSearchResult] {
    var byTitle: [String: AnimeSearchResult] = [:]
    var order: [String] = []
    for result in results {
        let key = result.title
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        if var existing = byTitle[key] {
            let episodes = (existing.episodes + result.episodes).sorted { $0.number < $1.number }
            var seen = Set<String>()
            existing.episodes = episodes.filter { seen.insert($0.identity.episodeID).inserted }
            existing.episodeCount = existing.episodes.count
            byTitle[key] = existing
        } else {
            byTitle[key] = result
            order.append(key)
        }
    }
    return order.compactMap { byTitle[$0] }
}
