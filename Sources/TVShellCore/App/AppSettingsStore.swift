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
    public var danmakuDisplaySettings: DanmakuDisplaySettings

    public init(
        apps: [TVAppProfile],
        displayScale: DisplayScale,
        wallpaperSource: WallpaperSource,
        webRemoteMode: WebRemoteMode,
        webZoom: Double,
        videoSourceLabel: String,
        animeSourceCatalog: AnimeSourceCatalogState,
        watchingHistory: [WatchHistoryEntry],
        danmakuDisplaySettings: DanmakuDisplaySettings = DanmakuDisplaySettings()
    ) {
        self.apps = apps
        self.displayScale = displayScale
        self.wallpaperSource = wallpaperSource
        self.webRemoteMode = webRemoteMode
        self.webZoom = webZoom
        self.videoSourceLabel = videoSourceLabel
        self.animeSourceCatalog = animeSourceCatalog
        self.watchingHistory = watchingHistory
        self.danmakuDisplaySettings = danmakuDisplaySettings
    }

    private enum CodingKeys: String, CodingKey {
        case apps
        case displayScale
        case wallpaperSource
        case webRemoteMode
        case webZoom
        case videoSourceLabel
        case animeSourceCatalog
        case watchingHistory
        case danmakuDisplaySettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apps = try container.decode([TVAppProfile].self, forKey: .apps)
        displayScale = try container.decode(DisplayScale.self, forKey: .displayScale)
        wallpaperSource = try container.decode(WallpaperSource.self, forKey: .wallpaperSource)
        webRemoteMode = try container.decode(WebRemoteMode.self, forKey: .webRemoteMode)
        webZoom = try container.decode(Double.self, forKey: .webZoom)
        videoSourceLabel = try container.decode(String.self, forKey: .videoSourceLabel)
        animeSourceCatalog = try container.decode(AnimeSourceCatalogState.self, forKey: .animeSourceCatalog)
        watchingHistory = try container.decodeIfPresent([WatchHistoryEntry].self, forKey: .watchingHistory) ?? []
        danmakuDisplaySettings = try container.decodeIfPresent(DanmakuDisplaySettings.self, forKey: .danmakuDisplaySettings) ?? DanmakuDisplaySettings()
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
