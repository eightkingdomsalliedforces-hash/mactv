import Foundation

public enum AnimeOfficialSource: String, Codable, CaseIterable, Equatable, Sendable {
    case aniGamer
    case officialYouTube

    public var title: String {
        switch self {
        case .aniGamer: "動畫瘋"
        case .officialYouTube: "官方 YouTube"
        }
    }
}

public struct AnimeOfficialSourceSession: Codable, Equatable, Sendable {
    public var query: String
    public var focusedIndex: Int
    public var historyIDs: [String]

    public init(query: String = "", focusedIndex: Int = 0, historyIDs: [String] = []) {
        self.query = query
        self.focusedIndex = max(0, focusedIndex)
        self.historyIDs = historyIDs
    }
}

public struct AnimeOfficialSourcesState: Codable, Equatable, Sendable {
    public var selectedSource: AnimeOfficialSource
    private var aniGamerSession: AnimeOfficialSourceSession
    private var officialYouTubeSession: AnimeOfficialSourceSession

    public init(
        selectedSource: AnimeOfficialSource = .aniGamer,
        aniGamerSession: AnimeOfficialSourceSession = .init(),
        officialYouTubeSession: AnimeOfficialSourceSession = .init()
    ) {
        self.selectedSource = selectedSource
        self.aniGamerSession = aniGamerSession
        self.officialYouTubeSession = officialYouTubeSession
    }

    public func session(for source: AnimeOfficialSource) -> AnimeOfficialSourceSession {
        switch source {
        case .aniGamer: aniGamerSession
        case .officialYouTube: officialYouTubeSession
        }
    }

    public mutating func updateQuery(_ query: String, for source: AnimeOfficialSource) {
        updateSession(for: source) { $0.query = query }
    }

    public mutating func updateFocus(_ index: Int, for source: AnimeOfficialSource) {
        updateSession(for: source) { $0.focusedIndex = max(0, index) }
    }

    public mutating func recordHistory(_ id: String, for source: AnimeOfficialSource) {
        updateSession(for: source) { session in
            session.historyIDs.removeAll { $0 == id }
            session.historyIDs.insert(id, at: 0)
        }
    }

    private mutating func updateSession(for source: AnimeOfficialSource, _ update: (inout AnimeOfficialSourceSession) -> Void) {
        switch source {
        case .aniGamer: update(&aniGamerSession)
        case .officialYouTube: update(&officialYouTubeSession)
        }
    }
}

public struct AniGamerCatalogItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let coverURL: URL?
    public let officialURL: URL

    public init(id: String, title: String, subtitle: String?, coverURL: URL?, officialURL: URL) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coverURL = coverURL
        self.officialURL = officialURL
    }
}

public enum AniGamerCatalog {
    public static let baseURL = URL(string: "https://ani.gamer.com.tw")!

    public static func searchRequest(keyword: String) -> AnimeHTTPRequest {
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return AnimeHTTPRequest(
            method: "POST",
            url: baseURL.appending(path: "search.php"),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                "User-Agent": "Mozilla/5.0 (Macintosh; Apple TV compatible) AppleWebKit/605.1.15",
                "Referer": baseURL.appending(path: "search.php").absoluteString
            ],
            body: Data((form.percentEncodedQuery ?? "").utf8)
        )
    }

    public static func decodeSearchHTML(_ data: Data) -> [AniGamerCatalogItem] {
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard let cardRegex = try? NSRegularExpression(
            pattern: #"<a[^>]+href=['\"]animeRef\.php\?sn=(\d+)['\"][^>]*>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return cardRegex.matches(in: html, range: range).compactMap { match in
            guard let idRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html)
            else { return nil }
            let id = String(html[idRange])
            guard seen.insert(id).inserted else { return nil }
            let body = String(html[bodyRange])
            let title = capture(#"<p[^>]*class=['\"][^'\"]*theme-name[^'\"]*['\"][^>]*>(.*?)</p>"#, in: body)
                ?? capture(#"\balt=['\"]([^'\"]+)['\"]"#, in: body)
            guard let title = title?.cleanAniGamerHTML, title.isEmpty == false,
                  let officialURL = URL(string: "animeRef.php?sn=\(id)", relativeTo: baseURL)?.absoluteURL
            else { return nil }
            let time = capture(#"<p[^>]*class=['\"][^'\"]*theme-time[^'\"]*['\"][^>]*>(.*?)</p>"#, in: body)?.cleanAniGamerHTML
            let count = capture(#"<span[^>]*class=['\"][^'\"]*theme-number[^'\"]*['\"][^>]*>(.*?)</span>"#, in: body)?.cleanAniGamerHTML
            let subtitle = [time, count].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: " · ")
            let cover = capture(#"\bdata-src=['\"]([^'\"]+)['\"]"#, in: body).flatMap(URL.init(string:))
            return AniGamerCatalogItem(
                id: id,
                title: title,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                coverURL: cover,
                officialURL: officialURL
            )
        }
    }

    private static func capture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let captured = Range(match.range(at: 1), in: value)
        else { return nil }
        return String(value[captured])
    }
}

private extension String {
    var cleanAniGamerHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
