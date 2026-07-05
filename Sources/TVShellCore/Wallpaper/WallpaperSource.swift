import Foundation

public struct WallpaperColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct WallpaperPalette: Codable, Equatable, Sendable {
    public let colors: [WallpaperColor]

    public init(colors: [WallpaperColor]) {
        self.colors = colors
    }
}

public enum WallpaperPreset: String, Codable, CaseIterable, Equatable, Sendable {
    case aurora
    case ocean
    case ember
    case graphite

    public var title: String {
        switch self {
        case .aurora: "Aurora"
        case .ocean: "Ocean"
        case .ember: "Ember"
        case .graphite: "Graphite"
        }
    }

    public var palette: WallpaperPalette {
        switch self {
        case .aurora:
            WallpaperPalette(colors: [
                WallpaperColor(red: 0.07, green: 0.12, blue: 0.22),
                WallpaperColor(red: 0.18, green: 0.24, blue: 0.46),
                WallpaperColor(red: 0.44, green: 0.18, blue: 0.42)
            ])
        case .ocean:
            WallpaperPalette(colors: [
                WallpaperColor(red: 0.02, green: 0.10, blue: 0.18),
                WallpaperColor(red: 0.02, green: 0.30, blue: 0.42),
                WallpaperColor(red: 0.10, green: 0.48, blue: 0.62)
            ])
        case .ember:
            WallpaperPalette(colors: [
                WallpaperColor(red: 0.18, green: 0.05, blue: 0.04),
                WallpaperColor(red: 0.52, green: 0.18, blue: 0.08),
                WallpaperColor(red: 0.88, green: 0.48, blue: 0.18)
            ])
        case .graphite:
            WallpaperPalette(colors: [
                WallpaperColor(red: 0.03, green: 0.04, blue: 0.06),
                WallpaperColor(red: 0.12, green: 0.14, blue: 0.18),
                WallpaperColor(red: 0.28, green: 0.30, blue: 0.36)
            ])
        }
    }

    public var next: WallpaperPreset {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    public var previous: WallpaperPreset {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index - 1 + all.count) % all.count]
    }
}

public enum WallpaperSource: Codable, Equatable, Sendable {
    case builtIn(WallpaperPreset)
    case localFile(URL)
    case remoteImage(URL)

    public var preset: WallpaperPreset? {
        if case let .builtIn(preset) = self {
            return preset
        }
        return nil
    }
}

public protocol WallpaperProvider: Sendable {
    func featured() -> WallpaperSource
    func next(after preset: WallpaperPreset) -> WallpaperSource
}

public struct StaticWallpaperProvider: WallpaperProvider {
    public let presets: [WallpaperPreset]

    public init(presets: [WallpaperPreset] = WallpaperPreset.allCases) {
        self.presets = presets.isEmpty ? WallpaperPreset.allCases : presets
    }

    public func featured() -> WallpaperSource {
        .builtIn(presets[0])
    }

    public func next(after preset: WallpaperPreset) -> WallpaperSource {
        guard let index = presets.firstIndex(of: preset) else {
            return featured()
        }
        return .builtIn(presets[(index + 1) % presets.count])
    }
}
