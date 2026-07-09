import Foundation

public struct AppCredentialsSnapshot: Codable, Equatable, Sendable {
    public var youtube: YouTubeCredentials
    public var dandanplay: DandanplayCredentials
    public var bilibili: BilibiliCredentials

    public init(
        youtube: YouTubeCredentials = .environment(),
        dandanplay: DandanplayCredentials = .environment(),
        bilibili: BilibiliCredentials = .environment()
    ) {
        self.youtube = youtube
        self.dandanplay = dandanplay
        self.bilibili = bilibili
    }
}

public struct AppCredentialsStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() -> AppCredentialsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppCredentialsStore(fileURL: base.appending(path: "MacTV/credentials.json"))
    }

    public static func userHome() -> AppCredentialsStore {
        AppCredentialsStore(fileURL: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("credentials.json"))
    }

    public func load() throws -> AppCredentialsSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppCredentialsSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppCredentialsSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func ensureTemplate() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) == false else {
            return
        }
        try save(AppCredentialsSnapshot(
            youtube: YouTubeCredentials(apiKey: ""),
            dandanplay: DandanplayCredentials(appID: "", appSecret: ""),
            bilibili: BilibiliCredentials(cookie: "")
        ))
    }
}
