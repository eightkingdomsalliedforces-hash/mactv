public enum SettingsFocus: String, Codable, Equatable, Sendable {
    case scale
    case wallpaper
    case webZoom
    case danmakuSize
    case danmakuSpeed
    case danmakuOpacity
    case danmakuDensity
    case videoSource
    case credentials

    public var next: SettingsFocus {
        switch self {
        case .scale: .wallpaper
        case .wallpaper: .webZoom
        case .webZoom: .videoSource
        case .videoSource: .danmakuSize
        case .danmakuSize: .danmakuSpeed
        case .danmakuSpeed: .danmakuOpacity
        case .danmakuOpacity: .danmakuDensity
        case .danmakuDensity: .credentials
        case .credentials: .credentials
        }
    }

    public var previous: SettingsFocus {
        switch self {
        case .scale: .scale
        case .wallpaper: .scale
        case .webZoom: .wallpaper
        case .videoSource: .webZoom
        case .danmakuSize: .videoSource
        case .danmakuSpeed: .danmakuSize
        case .danmakuOpacity: .danmakuSpeed
        case .danmakuDensity: .danmakuOpacity
        case .credentials: .danmakuDensity
        }
    }

    public var isAdjustable: Bool {
        switch self {
        case .videoSource, .credentials:
            false
        default:
            true
        }
    }
}
