import Foundation

public protocol AnimeHTTPTransport: Sendable {
    func data(for request: AnimeHTTPRequest) async throws -> Data
}

public struct URLSessionAnimeHTTPTransport: AnimeHTTPTransport {
    public let requestTimeout: TimeInterval

    public init(requestTimeout: TimeInterval = 8) {
        self.requestTimeout = max(1, requestTimeout)
    }

    public func data(for request: AnimeHTTPRequest) async throws -> Data {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = requestTimeout
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await URLSession.shared.data(for: urlRequest)
            try Task.checkCancellation()
        } catch let error as URLError where error.code == .timedOut {
            throw AnimeHTTPError.timedOut(request.url.absoluteString)
        }
        if let response = response as? HTTPURLResponse,
           (200..<300).contains(response.statusCode) == false {
            throw AnimeHTTPError.badStatus(response.statusCode)
        }
        return data
    }
}

public final class StaticAnimeHTTPTransport: AnimeHTTPTransport, @unchecked Sendable {
    public private(set) var requests: [AnimeHTTPRequest] = []
    private let routes: [String: Data]

    public init(routes: [String: Data]) {
        self.routes = routes
    }

    public func data(for request: AnimeHTTPRequest) async throws -> Data {
        requests.append(request)
        guard let data = routes[request.url.absoluteString] else {
            throw AnimeHTTPError.missingRoute(request.url.absoluteString)
        }
        return data
    }
}

public enum AnimeHTTPError: Error, Equatable, Sendable {
    case badStatus(Int)
    case missingRoute(String)
    case missingCredentials
    case timedOut(String)
}

public struct DandanplayCredentials: Codable, Equatable, Sendable {
    public var appID: String
    public var appSecret: String

    public init(appID: String, appSecret: String) {
        self.appID = appID
        self.appSecret = appSecret
    }

    public static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> DandanplayCredentials {
        DandanplayCredentials(
            appID: environment["TVSHELL_DANDANPLAY_APP_ID"] ?? "",
            appSecret: environment["TVSHELL_DANDANPLAY_APP_SECRET"] ?? ""
        )
    }

    public var isConfigured: Bool {
        appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

public struct DandanplayDanmakuProvider: DanmakuProvider {
    private let credentials: DandanplayCredentials
    private let timestamp: Int
    private let transport: any AnimeHTTPTransport

    public init(
        credentials: DandanplayCredentials,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        transport: any AnimeHTTPTransport = URLSessionAnimeHTTPTransport()
    ) {
        self.credentials = credentials
        self.timestamp = timestamp
        self.transport = transport
    }

    public func comments(for episode: AnimeEpisodeIdentity) async throws -> [DanmakuComment] {
        guard credentials.isConfigured else {
            throw AnimeHTTPError.missingCredentials
        }

        let episodeID = try await resolvedEpisodeID(for: episode)
        let request = DandanplayAPI.commentRequest(
            episodeID: episodeID,
            appID: credentials.appID,
            appSecret: credentials.appSecret,
            timestamp: timestamp
        )
        let data = try await transport.data(for: request)
        return try DandanplayAPI.decodeComments(data)
    }

    private func resolvedEpisodeID(for episode: AnimeEpisodeIdentity) async throws -> String {
        if episode.episodeID.count >= 6,
           episode.episodeID.allSatisfy(\.isNumber) {
            return episode.episodeID
        }

        let preferredEpisode = Int(episode.episodeID.filter(\.isNumber)) ?? 1
        let request = DandanplayAPI.searchEpisodesRequest(
            anime: episode.subjectID,
            episode: preferredEpisode,
            appID: credentials.appID,
            appSecret: credentials.appSecret,
            timestamp: timestamp
        )
        let data = try await transport.data(for: request)
        guard let matchedID = try DandanplayAPI.decodeEpisodeSearch(data, preferredEpisode: preferredEpisode) else {
            throw AnimeHTTPError.missingRoute("dandanplay episode id: \(episode.subjectID) #\(preferredEpisode)")
        }
        return matchedID
    }
}
