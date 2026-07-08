import Foundation

public struct AppSettingsSnapshot: Codable, Equatable, Sendable {
    public var apps: [TVAppProfile]
    public var displayScale: DisplayScale
    public var wallpaperSource: WallpaperSource
    public var webRemoteMode: WebRemoteMode
    public var webZoom: Double
    public var videoSourceLabel: String
    public var animeSourceCatalog: AnimeSourceCatalogState
    public var watchingHistory: [WatchHistoryEntry]

    public init(
        apps: [TVAppProfile],
        displayScale: DisplayScale,
        wallpaperSource: WallpaperSource,
        webRemoteMode: WebRemoteMode,
        webZoom: Double,
        videoSourceLabel: String,
        animeSourceCatalog: AnimeSourceCatalogState,
        watchingHistory: [WatchHistoryEntry]
    ) {
        self.apps = apps
        self.displayScale = displayScale
        self.wallpaperSource = wallpaperSource
        self.webRemoteMode = webRemoteMode
        self.webZoom = webZoom
        self.videoSourceLabel = videoSourceLabel
        self.animeSourceCatalog = animeSourceCatalog
        self.watchingHistory = watchingHistory
    }
}

public struct AppSettingsStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func applicationSupport() -> AppSettingsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppSettingsStore(fileURL: base.appending(path: "MacTV/settings.json"))
    }

    public func load() throws -> AppSettingsSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
    }

    public func save(_ snapshot: AppSettingsSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}
