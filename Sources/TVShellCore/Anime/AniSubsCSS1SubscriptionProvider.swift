import Foundation

public enum AniSubsCSS1ProviderError: LocalizedError, Equatable, Sendable {
    case allSourcesFailed([String])

    public var errorDescription: String? {
        switch self {
        case let .allSourcesFailed(reasons):
            "CSS1 來源解析失敗：\(reasons.joined(separator: "；"))"
        }
    }
}

public struct AniSubsCSS1SubscriptionProvider: AnimeMediaSourceAdapter {
    public let id = "ani-subs-css1"
    public let displayName = "ani-subs CSS1"
    public let resolverKind: AnimeResolverKind = .http

    private let subscriptionURL: URL
    private let transport: any AnimeHTTPTransport
    private let requestTimeoutNanoseconds: UInt64
    private let healthStore: AniSubsCSS1SourceHealthStore

    public init(
        subscriptionURL: URL = URL(string: "https://sub.creamycake.org/v1/css1.json")!,
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport(),
        requestTimeoutNanoseconds: UInt64 = 8_000_000_000,
        healthStore: AniSubsCSS1SourceHealthStore = .applicationSupport()
    ) {
        self.subscriptionURL = subscriptionURL
        self.transport = transport
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.healthStore = healthStore
    }

    public func search(_ query: AnimeSearchQuery) async throws -> [AnimeSearchResult] {
        let healthState = (try? healthStore.load()) ?? AniSubsCSS1SourceHealthState()
        let sources = try await webSelectorSources()
            .filter { healthState.skippedSourceNames.contains($0.name) == false }
        var allResults: [AnimeSearchResult] = []
        var failureReasons: [String] = []

        for source in sources {
            var producedResult = false
            var detailFailureReason: String?
            let subjects: [CSS1HTMLSelectorEngine.Anchor]
            let searchHTML: String
            do {
                let searchURL = try source.searchURL(keyword: query.keyword)
                searchHTML = try await html(for: searchURL, source: source)
                subjects = CSS1HTMLSelectorEngine.anchors(
                    matching: source.searchSelector,
                    in: searchHTML,
                    baseURL: searchURL
                )
            } catch {
                let reason = css1FailureReason(error)
                failureReasons.append("\(source.name)：\(reason)")
                try? healthStore.recordFailure(sourceName: source.name, reason: reason)
                continue
            }

            let matchedSubjects = filteredSubjects(subjects, keyword: query.keyword)
            for subject in matchedSubjects.prefix(20) {
                do {
                    guard isAnimeSearchCard(subject, in: searchHTML) else {
                        continue
                    }
                    let detailHTML = try await html(for: subject.url, source: source)
                    guard isAnimeDetailPage(detailHTML) else {
                        continue
                    }
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
                    producedResult = true
                } catch {
                    let reason = css1FailureReason(error)
                    detailFailureReason = reason
                    if failureReasons.contains(where: { $0.hasPrefix("\(source.name)：") }) == false {
                        failureReasons.append("\(source.name)：\(reason)")
                    }
                    continue
                }
            }
            if producedResult {
                try? healthStore.recordSuccess(sourceName: source.name)
            } else if let detailFailureReason {
                try? healthStore.recordFailure(sourceName: source.name, reason: detailFailureReason)
            }
        }

        // Enrich before deduplicating so same-title live-action pages cannot
        // win merely because they expose more episodes than the animation.
        let enriched = await enrichWithBangumi(allResults)
        let merged = Array(mergeCSS1Results(enriched).prefix(60))
        if merged.isEmpty, failureReasons.isEmpty == false {
            throw AniSubsCSS1ProviderError.allSourcesFailed(failureReasons)
        }
        return merged
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
        let lines = episode.playbackLines ?? episode.identity.playbackURL.map {
            [AnimeEpisodePlaybackLine(id: episode.id, title: "播放線 1", sourceName: css1SourceName(for: episode), playbackURL: $0)]
        } ?? []
        guard lines.isEmpty == false else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 playback url: \(episode.identity.episodeID)")
        }
        let source = try await source(named: css1SourceName(for: episode))
        var candidates: [AnimeStreamCandidate] = []
        for (index, line) in lines.enumerated() {
            do {
            let watchHTML = try await html(for: line.playbackURL, source: source)
        let playbackHTML: String
        let playbackBaseURL: URL
        if source.enableNestedURL,
           let nestedURL = CSS1HTMLSelectorEngine.firstNestedURL(
                in: watchHTML,
                pattern: source.nestedURLPattern,
                baseURL: line.playbackURL
           ) {
            playbackHTML = try await html(for: nestedURL, source: source)
            playbackBaseURL = nestedURL
        } else {
            playbackHTML = watchHTML
            playbackBaseURL = line.playbackURL
        }
        guard let streamURL = CSS1HTMLSelectorEngine.firstVideoURL(
            in: playbackHTML,
            pattern: source.videoPattern,
            baseURL: playbackBaseURL
        ) else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 video url: \(line.playbackURL.absoluteString)")
        }

            candidates.append(AnimeStreamCandidate(
                url: streamURL,
                quality: "CSS1",
                priority: 64 - index,
                headers: [
                    "resolver": "web-selector",
                    "source": source.name,
                    "title": "\(episode.identity.subjectID) · \(line.title)",
                    "episode": episode.title,
                    "User-Agent": source.userAgent
                ].merging(source.videoHeaders, uniquingKeysWith: { _, new in new })
            ))
            } catch {
                continue
            }
        }
        guard candidates.isEmpty == false else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 video url: \(episode.identity.episodeID)")
        }
        return candidates
    }

    private func source(named name: String) async throws -> AniSubsCSS1Source {
        let healthState = (try? healthStore.load()) ?? AniSubsCSS1SourceHealthState()
        let sources = try await webSelectorSources()
            .filter { healthState.skippedSourceNames.contains($0.name) == false }
        guard let source = sources.first(where: { $0.name == name }) ?? sources.first else {
            throw AnimeHTTPError.missingRoute("ani-subs css1 source")
        }
        return source
    }

    private func webSelectorSources() async throws -> [AniSubsCSS1Source] {
        let data = try await withCSS1Timeout(secondsLabel: "subscription") {
            try await transport.data(for: AnimeHTTPRequest(
            method: "GET",
            url: subscriptionURL,
            headers: [
                "Accept": "application/json",
                "User-Agent": "TVShell/0.1 ani-subs-css1"
            ]
            ))
        }
        return try AniSubsCSS1Subscription.decode(data)
    }

    private func html(for url: URL, source: AniSubsCSS1Source) async throws -> String {
        let data = try await withCSS1Timeout(secondsLabel: url.host ?? url.absoluteString) {
            try await transport.data(for: AnimeHTTPRequest(
                method: "GET",
                url: url,
                headers: source.requestHeaders
            ))
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        if let captcha = CSS1HTMLSelectorEngine.detectCaptcha(url: url, html: html) {
            throw SelectorAnimeSourceError.captchaRequired(captcha)
        }
        return html
    }

    private func filteredSubjects(
        _ subjects: [CSS1HTMLSelectorEngine.Anchor],
        keyword: String
    ) -> [CSS1HTMLSelectorEngine.Anchor] {
        let keywordKey = normalizedSearchKey(keyword)
        guard keywordKey.isEmpty == false else {
            return subjects
        }
        return subjects.filter { subject in
            let titleKey = normalizedSearchKey(subject.title)
            guard titleKey.isEmpty == false else {
                return false
            }
            return (titleKey.contains(keywordKey) || keywordKey.contains(titleKey))
                && isLiveActionTitle(subject.title) == false
        }
    }

    private func isLiveActionTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        return ["真人", "日劇", "韩剧", "韓劇", "偶像劇", "电视剧", "電視劇", "ドラマ", "live action", "drama"]
            .contains { lowercased.contains($0.lowercased()) }
    }

    private func isAnimeDetailPage(_ html: String) -> Bool {
        let categoryBlocks = CSS1HTMLSelectorEngine.blocks(matching: ".module-info-tag-link", in: html)
        let categories = categoryBlocks.flatMap { block in
            CSS1HTMLSelectorEngine.texts(matching: "a", in: block)
        }
        return isAnimeCategoryText(categories.joined(separator: " "))
    }

    private func isAnimeSearchCard(_ subject: CSS1HTMLSelectorEngine.Anchor, in html: String) -> Bool {
        for selector in [".module-card-item", ".post-list", ".vodlist", ".search-item"] {
            if let card = CSS1HTMLSelectorEngine.blocks(matching: selector, in: html)
                .first(where: { $0.contains(subject.url.path) }) {
                return isAnimeCategoryText(card)
            }
        }
        return isAnimeCategoryText(searchContext(for: subject.url, in: html))
    }

    private func searchContext(for url: URL, in html: String) -> String {
        guard let match = html.range(of: url.path) else {
            return ""
        }
        let start = html.index(match.lowerBound, offsetBy: -360, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(match.upperBound, offsetBy: 240, limitedBy: html.endIndex) ?? html.endIndex
        return String(html[start..<end])
    }

    private func isAnimeCategoryText(_ value: String) -> Bool {
        let categoryText = value.lowercased()
        guard categoryText.isEmpty == false else {
            return true
        }

        let nonAnimeCategories = [
            "連續劇", "连续剧", "日劇", "日剧", "韓劇", "韩剧", "電視劇", "电视剧",
            "真人", "電影", "电影", "綜藝", "综艺", "紀錄片", "纪录片"
        ]
        return nonAnimeCategories.contains { categoryText.contains($0.lowercased()) } == false
    }

    private func normalizedSearchKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\s\p{P}\p{S}_]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func withCSS1Timeout<T: Sendable>(
        secondsLabel: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
                throw AnimeHTTPError.missingRoute("ani-subs CSS1 request timeout: \(secondsLabel)")
            }
            guard let result = try await group.next() else {
                throw AnimeHTTPError.missingRoute("ani-subs CSS1 request timeout: \(secondsLabel)")
            }
            group.cancelAll()
            return result
        }
    }

    private func parseEpisodes(
        source: AniSubsCSS1Source,
        subjectTitle: String,
        detailHTML: String,
        detailURL: URL
    ) -> [AnimeEpisode] {
        let episodeHTML = CSS1HTMLSelectorEngine.blocks(matching: source.episodeListSelector, in: detailHTML)
            .joined(separator: "\n")
        let narrowedAnchors = CSS1HTMLSelectorEngine.episodeAnchors(
            titleSelector: source.episodeSelector,
            linkSelector: source.episodeLinkSelector,
            in: episodeHTML,
            baseURL: detailURL
        )
        let fullAnchors = CSS1HTMLSelectorEngine.episodeAnchors(
            titleSelector: source.episodeSelector,
            linkSelector: source.episodeLinkSelector,
            in: detailHTML,
            baseURL: detailURL
        )
        let anchors = (narrowedAnchors.isEmpty ? fullAnchors : narrowedAnchors)
            .filter { anchor in
                CSS1HTMLSelectorEngine.isEpisodeAnchor(
                    anchor,
                    subjectTitle: subjectTitle,
                    sortPattern: source.episodeSortPattern
                )
            }

        var episodesByNumber: [Int: AnimeEpisode] = [:]
        var orderedNumbers: [Int] = []
        for (offset, anchor) in anchors.enumerated() {
            let number = CSS1HTMLSelectorEngine.episodeNumber(
                from: anchor.title,
                pattern: source.episodeSortPattern
            ) ?? offset + 1
            let line = AnimeEpisodePlaybackLine(
                id: "\(id)-\(stableID(anchor.url.absoluteString))",
                title: "播放線 \((episodesByNumber[number]?.playbackLines?.count ?? 0) + 1)",
                sourceName: source.name,
                playbackURL: anchor.url
            )
            if var existing = episodesByNumber[number] {
                existing.playbackLines = (existing.playbackLines ?? []) + [line]
                episodesByNumber[number] = existing
                continue
            }
            orderedNumbers.append(number)
            episodesByNumber[number] = AnimeEpisode(
                id: "\(id)-\(stableID(source.name))-\(stableID(anchor.url.absoluteString))",
                title: anchor.title,
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: id,
                    subjectID: subjectTitle,
                    episodeID: anchor.url.absoluteString,
                    subjectAliases: [subjectTitle, css1SourceMarker(source.name)],
                    playbackURL: anchor.url
                ),
                playbackLines: [line]
            )
        }
        return orderedNumbers.compactMap { episodesByNumber[$0] }
    }

    private func css1SourceMarker(_ sourceName: String) -> String {
        "css1-source:\(sourceName)"
    }

    private func css1SourceName(for episode: AnimeEpisode) -> String {
        let prefix = "css1-source:"
        return episode.identity.subjectAliases
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
            ?? id
    }

    private func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func enrichWithBangumi(_ results: [AnimeSearchResult]) async -> [AnimeSearchResult] {
        var enriched: [AnimeSearchResult] = []
        for result in results {
            guard let subject = await bangumiSubject(keyword: result.title) else {
                enriched.append(result)
                continue
            }
            var item = result
            item.title = subject.title
            item.subtitle = subject.summary?.nilIfBlank ?? result.subtitle
            item.coverURL = subject.coverURL ?? result.coverURL
            item.originalTitle = subject.name.nilIfBlank ?? result.originalTitle
            item.airDate = subject.date?.nilIfBlank ?? result.airDate
            item.score = subject.rating?.score ?? result.score
            item.rank = subject.rank ?? result.rank
            item.episodeCount = subject.episodeCount ?? result.episodeCount
            item.episodes = result.episodes.map { episode in
                var copy = episode
                copy.identity.subjectID = item.title
                copy.identity.subjectAliases = uniqueNonEmpty(copy.identity.subjectAliases + [item.title, subject.name, result.title])
                return copy
            }
            enriched.append(item)
        }
        return enriched
    }

    private func bangumiSubject(keyword: String) async -> BangumiSubject? {
        do {
            let request = try BangumiAPI.searchSubjectsRequest(keyword: keyword)
            let data = try await transport.data(for: request)
            let subjects = try BangumiAPI.decodeSubjectSearch(data)
            return subjects.first { subject in
                normalizedSearchKey(subject.title) == normalizedSearchKey(keyword)
                    || normalizedSearchKey(subject.name) == normalizedSearchKey(keyword)
            } ?? subjects.first
        } catch {
            return nil
        }
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false,
                  seen.insert(trimmed.lowercased()).inserted
            else {
                return nil
            }
            return trimmed
        }
    }
}

private func css1FailureReason(_ error: Error) -> String {
    if let localized = error as? LocalizedError,
       let description = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
       description.isEmpty == false {
        return description
    }
    return String(describing: error)
}

public struct AniSubsCSS1Source: Equatable, Sendable {
    public var name: String
    public var searchURLTemplate: String
    public var searchSelector: String
    public var episodeListSelector: String
    public var episodeSelector: String
    public var episodeLinkSelector: String?
    public var episodeSortPattern: String?
    public var enableNestedURL: Bool
    public var nestedURLPattern: String?
    public var videoPattern: String
    public var userAgent: String
    public var videoHeaders: [String: String]

    var requestHeaders: [String: String] {
        var headers = [
            "Accept": "text/html,application/xhtml+xml",
            "User-Agent": userAgent
        ]
        if let cookie = videoHeaders["Cookie"], cookie.isEmpty == false {
            headers["Cookie"] = cookie
        }
        return headers
    }

    func searchURL(keyword: String) throws -> URL {
        let encodedKeyword = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let value = searchURLTemplate.replacingOccurrences(of: "{keyword}", with: encodedKeyword)
        guard let url = URL(string: value) else {
            throw SelectorAnimeSourceError.invalidSearchURL
        }
        return url
    }
}

public struct AniSubsCSS1SourceHealthState: Codable, Equatable, Sendable {
    public var disabledSources: [String: AniSubsCSS1DisabledSource]

    public init(disabledSources: [String: AniSubsCSS1DisabledSource] = [:]) {
        self.disabledSources = disabledSources
    }

    public var disabledSourceNames: Set<String> {
        Set(disabledSources.keys)
    }

    public var skippedSourceNames: Set<String> {
        Set(disabledSources.compactMap { name, disabledSource in
            disabledSource.shouldSkipAutomatically ? name : nil
        })
    }
}

public struct AniSubsCSS1DisabledSource: Codable, Equatable, Sendable {
    public var reason: String
    public var disabledAt: Date

    public init(reason: String, disabledAt: Date = Date()) {
        self.reason = reason
        self.disabledAt = disabledAt
    }

    var shouldSkipAutomatically: Bool {
        let lowercasedReason = reason.lowercased()
        return lowercasedReason.contains("request timeout")
            || lowercasedReason.contains("timed out")
            || lowercasedReason.contains("captcha")
            || lowercasedReason.contains("cloudflare")
            || lowercasedReason.contains("驗證")
            || lowercasedReason.contains("验证")
    }
}

public struct AniSubsCSS1SourceHealthStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() -> AniSubsCSS1SourceHealthStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AniSubsCSS1SourceHealthStore(fileURL: base.appending(path: "MacTV/css1-disabled-sources.json"))
    }

    public func load() throws -> AniSubsCSS1SourceHealthState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AniSubsCSS1SourceHealthState()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AniSubsCSS1SourceHealthState.self, from: data)
    }

    public func save(_ state: AniSubsCSS1SourceHealthState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func recordFailure(sourceName: String, reason: String) throws {
        var state = try load()
        state.disabledSources[sourceName] = AniSubsCSS1DisabledSource(reason: reason)
        try save(state)
    }

    public func recordSuccess(sourceName: String) throws {
        var state = try load()
        guard state.disabledSources[sourceName] != nil else {
            return
        }
        state.disabledSources[sourceName] = nil
        try save(state)
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
                episodeLinkSelector: searchConfig.selectorChannelFormatFlattened?.selectEpisodeLinksFromList?.nilIfBlank
                    ?? searchConfig.selectorChannelFormatNoChannel?.selectEpisodeLinks?.nilIfBlank,
                episodeSortPattern: searchConfig.selectorChannelFormatFlattened?.matchEpisodeSortFromName,
                enableNestedURL: searchConfig.matchVideo?.enableNestedUrl ?? false,
                nestedURLPattern: searchConfig.matchVideo?.matchNestedUrl?.nilIfBlank,
                videoPattern: videoPattern,
                userAgent: source.arguments.userAgent
                    ?? searchConfig.matchVideo?.addHeadersToVideo?.userAgent
                    ?? "TVShell/0.1 ani-subs-css1",
                videoHeaders: searchConfig.matchVideo?.normalizedVideoHeaders ?? [:]
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
    var selectorChannelFormatNoChannel: AniSubsCSS1NoChannelEpisodeSelector?
    var matchVideo: AniSubsCSS1VideoMatcher?
}

private struct AniSubsCSS1SubjectSelector: Decodable {
    var selectLists: String?
}

private struct AniSubsCSS1EpisodeSelector: Decodable {
    var selectEpisodeLists: String?
    var selectEpisodesFromList: String?
    var selectEpisodeLinksFromList: String?
    var matchEpisodeSortFromName: String?
}

private struct AniSubsCSS1VideoMatcher: Decodable {
    var enableNestedUrl: Bool?
    var matchNestedUrl: String?
    var matchVideoUrl: String?
    var cookies: String?
    var addHeadersToVideo: AniSubsCSS1VideoHeaders?

    var normalizedVideoHeaders: [String: String] {
        var headers = addHeadersToVideo?.normalized ?? [:]
        if let cookies = cookies?.nilIfBlank {
            headers["Cookie"] = cookies
        }
        return headers
    }
}

private struct AniSubsCSS1NoChannelEpisodeSelector: Decodable {
    var selectEpisodes: String?
    var selectEpisodeLinks: String?
    var matchEpisodeSortFromName: String?
}

private struct AniSubsCSS1VideoHeaders: Decodable {
    var referer: String?
    var userAgent: String?

    var normalized: [String: String] {
        var headers: [String: String] = [:]
        if let referer = referer?.nilIfBlank {
            headers["Referer"] = referer
        }
        if let userAgent = userAgent?.nilIfBlank {
            headers["User-Agent"] = userAgent
        }
        return headers
    }
}

private enum CSS1HTMLSelectorEngine {
    struct Anchor: Equatable {
        var title: String
        var url: URL
    }

    static func episodeAnchors(
        titleSelector: String,
        linkSelector: String?,
        in html: String,
        baseURL: URL
    ) -> [Anchor] {
        guard let linkSelector, linkSelector.isEmpty == false else {
            return anchors(matching: titleSelector, in: html, baseURL: baseURL)
        }

        let titles = texts(matching: titleSelector, in: html)
        let links = anchors(matching: linkSelector, in: html, baseURL: baseURL)
        guard links.isEmpty == false else {
            return []
        }

        return links.enumerated().map { index, link in
            guard titles.indices.contains(index), titles[index].isEmpty == false else {
                return link
            }
            return Anchor(title: titles[index], url: link.url)
        }
    }

    static func isEpisodeAnchor(
        _ anchor: Anchor,
        subjectTitle: String,
        sortPattern: String?
    ) -> Bool {
        let title = normalize(anchor.title)
        guard title.isEmpty == false,
              normalizedComparable(title) != normalizedComparable(subjectTitle)
        else {
            return false
        }

        let hasEpisodeLabel = title.range(
            of: #"(?:ep\.?\s*\d+|第\s*\d+\s*[話话集]|\b\d+\s*(?:話|话|集)\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let isPureEpisodeNumber = title.range(
            of: #"^(?:ep\.?\s*)?\d+(?:\s*(?:v\d+|sp|ova))?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if hasEpisodeLabel || isPureEpisodeNumber {
            return true
        }

        let path = anchor.url.path.lowercased()
        let hasPlaybackPath = path.range(of: #"(?:play|episode|vod|watch|detail)[/_-]"#, options: .regularExpression) != nil
        return hasPlaybackPath && (episodeNumber(from: title, pattern: sortPattern) != nil && hasEpisodeLabel)
    }

    static func anchors(matching selector: String, in html: String, baseURL: URL) -> [Anchor] {
        let requiredClasses = classNames(in: selector)
        let expectedTag = tagName(in: selector)
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
            if let expectedTag, expectedTag != "a" {
                return nil
            }
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

    static func texts(matching selector: String, in html: String) -> [String] {
        let expectedTag = tagName(in: selector)
        let requiredClasses = classNames(in: selector)
        let pattern: String
        if let expectedTag {
            pattern = #"<(?<tag>"# + NSRegularExpression.escapedPattern(for: expectedTag) + #")\b(?<attrs>[^>]*)>(?<body>.*?)</"# + NSRegularExpression.escapedPattern(for: expectedTag) + #">"#
        } else {
            pattern = #"<(?<tag>[a-zA-Z0-9]+)\b(?<attrs>[^>]*)>(?<body>.*?)</\k<tag>>"#
        }
        let elementRegex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return elementRegex?.matches(in: html, range: nsRange).compactMap { match in
            guard let tagRange = Range(match.range(withName: "tag"), in: html),
                  let attrsRange = Range(match.range(withName: "attrs"), in: html),
                  let bodyRange = Range(match.range(withName: "body"), in: html)
            else {
                return nil
            }
            let tag = String(html[tagRange]).lowercased()
            let attrs = String(html[attrsRange])
            if let expectedTag, expectedTag != tag {
                return nil
            }
            if requiredClasses.isEmpty == false,
               requiredClasses.allSatisfy({ attrs.contains($0) }) == false {
                return nil
            }
            let text = normalize(stripHTML(String(html[bodyRange])))
            return text.isEmpty ? nil : text
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
            if let attrsRange = Range(match.range, in: html),
               let balanced = balancedBlockBody(startingAt: attrsRange.lowerBound, in: html, requiredClass: firstClass) {
                return balanced
            }
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
        let documents = Array(Set([normalizedHTML, normalizedHTML.removingPercentEncoding ?? normalizedHTML]))

        for document in documents {
            if let url = firstVideoURLByQueryParameter(in: document, baseURL: baseURL) {
                return url
            }
        }

        let normalizedPattern = pattern.replacingOccurrences(of: #"\\/"#, with: "/")
        let hasNamedVideoGroup = normalizedPattern.contains("(?<v>")
        if let regex = try? NSRegularExpression(pattern: normalizedPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            for document in documents {
                let nsRange = NSRange(document.startIndex..<document.endIndex, in: document)
                for match in regex.matches(in: document, range: nsRange) {
                    if hasNamedVideoGroup,
                       let range = Range(match.range(withName: "v"), in: document),
                       let url = resolveVideoURL(cleanURLCandidate(String(document[range])), relativeTo: baseURL) {
                        return url
                    }
                    for group in 1..<match.numberOfRanges {
                        guard let range = Range(match.range(at: group), in: document),
                              let url = resolveVideoURL(cleanURLCandidate(String(document[range])), relativeTo: baseURL)
                        else {
                            continue
                        }
                        return url
                    }
                }
            }
        }

        let fallbackPattern = #"https?://[^"'\s<>\\]+?\.(?:mp4|m3u8|flv|mkv)(?:\?[^"'\s<>\\]+)?"#
        guard let fallback = try? NSRegularExpression(pattern: fallbackPattern, options: [.caseInsensitive]) else {
            return nil
        }
        for document in documents {
            let nsRange = NSRange(document.startIndex..<document.endIndex, in: document)
            guard let match = fallback.firstMatch(in: document, range: nsRange),
                  let range = Range(match.range, in: document),
                  let url = resolveVideoURL(cleanURLCandidate(String(document[range])), relativeTo: baseURL)
            else {
                continue
            }
            return url
        }
        return nil
    }

    static func firstNestedURL(in html: String, pattern: String?, baseURL: URL) -> URL? {
        guard let pattern, pattern.isEmpty == false else {
            return nil
        }
        let normalizedHTML = html
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u002F"#, with: "/")
        guard let regex = try? NSRegularExpression(
            pattern: pattern.replacingOccurrences(of: #"\\/"#, with: "/"),
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let nsRange = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
        guard let match = regex.firstMatch(in: normalizedHTML, range: nsRange) else {
            return nil
        }
        for group in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: group), in: normalizedHTML),
                  let url = resolveURL(cleanURLCandidate(String(normalizedHTML[range])), relativeTo: baseURL)
            else {
                continue
            }
            return url
        }
        guard let range = Range(match.range, in: normalizedHTML) else {
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

    private static func tagName(in selector: String) -> String? {
        let lastComponent = selector
            .split(separator: ">")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? selector
        guard let regex = try? NSRegularExpression(pattern: #"^([A-Za-z][A-Za-z0-9_-]*)"#),
              let match = regex.firstMatch(in: lastComponent, range: NSRange(lastComponent.startIndex..<lastComponent.endIndex, in: lastComponent)),
              let range = Range(match.range(at: 1), in: lastComponent)
        else {
            return nil
        }
        return String(lastComponent[range]).lowercased()
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

    private static func balancedBlockBody(startingAt start: String.Index, in html: String, requiredClass: String) -> String? {
        guard let startMatch = firstTag(from: start, in: html),
              startMatch.opening,
              startMatch.attributes.contains(requiredClass),
              let bodyStart = startMatch.end
        else {
            return nil
        }

        var depth = 1
        var cursor = bodyStart
        while cursor < html.endIndex,
              let tag = firstTag(from: cursor, in: html) {
            if tag.name == startMatch.name {
                depth += tag.opening ? 1 : -1
                if depth == 0 {
                    return String(html[bodyStart..<tag.start])
                }
            }
            cursor = tag.end ?? html.index(after: cursor)
        }
        return nil
    }

    private static func firstTag(from start: String.Index, in html: String) -> (name: String, attributes: String, opening: Bool, start: String.Index, end: String.Index?)? {
        guard let open = html[start...].firstIndex(of: "<"),
              let close = html[open...].firstIndex(of: ">") else {
            return nil
        }
        let raw = String(html[html.index(after: open)..<close])
        guard raw.hasPrefix("!") == false,
              raw.hasPrefix("?") == false else {
            return firstTag(from: html.index(after: close), in: html)
        }
        let opening = raw.hasPrefix("/") == false
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard let name = cleaned.split(whereSeparator: \.isWhitespace).first?.lowercased() else {
            return firstTag(from: html.index(after: close), in: html)
        }
        return (name, cleaned, opening, open, html.index(after: close))
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

    private static func normalizedComparable(_ value: String) -> String {
        normalize(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\s\p{P}\p{S}_]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func cleanURLCandidate(_ value: String) -> String {
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: #" "';)"#).union(.whitespacesAndNewlines))
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")
        return cleaned.removingPercentEncoding ?? cleaned
    }

    private static func firstVideoURLByQueryParameter(in html: String, baseURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|[?&"'`\s])(?:url|v|video|src)=([^&"'`\s<>]+)"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: nsRange) {
            guard let range = Range(match.range(at: 1), in: html),
                  let url = resolveVideoURL(cleanURLCandidate(String(html[range])), relativeTo: baseURL)
            else {
                continue
            }
            return url
        }
        return nil
    }

    private static func resolveVideoURL(_ rawValue: String, relativeTo baseURL: URL) -> URL? {
        let value = cleanURLCandidate(rawValue)
        guard value.range(of: #"\.(mp4|m3u8|flv|mkv)(?:\?|$)"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return resolveURL(value, relativeTo: baseURL)
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
        if let existing = byTitle[key] {
            byTitle[key] = preferredCSS1Result(existing, result)
        } else {
            byTitle[key] = result
            order.append(key)
        }
    }
    return order.compactMap { byTitle[$0] }
}

private func preferredCSS1Result(_ left: AnimeSearchResult, _ right: AnimeSearchResult) -> AnimeSearchResult {
    let leftDistance = episodeCountDistance(for: left)
    let rightDistance = episodeCountDistance(for: right)
    if leftDistance != rightDistance {
        return leftDistance < rightDistance ? left : right
    }
    if (left.coverURL != nil) != (right.coverURL != nil) {
        return left.coverURL != nil ? left : right
    }
    return left
}

private func episodeCountDistance(for result: AnimeSearchResult) -> Int {
    guard let expected = result.episodeCount, expected > 0 else {
        return 0
    }
    return abs(result.episodes.count - expected)
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
