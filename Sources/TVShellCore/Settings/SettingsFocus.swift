public enum SettingsFocus: String, Codable, Equatable, Sendable {
    case scale
    case wallpaper

    public var next: SettingsFocus {
        switch self {
        case .scale: .wallpaper
        case .wallpaper: .scale
        }
    }

    public var previous: SettingsFocus {
        switch self {
        case .scale: .wallpaper
        case .wallpaper: .scale
        }
    }
}
