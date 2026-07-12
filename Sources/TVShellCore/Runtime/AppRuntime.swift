import Foundation

public enum RuntimeKind: String, Codable, Equatable, Sendable {
    case launcher
    case web
    case native
    case remoteLearning
}

public enum LaunchTarget: Equatable, Codable, Sendable {
    case web(URL)
    case portableWeb(entrypoint: URL, allowedHosts: [String])
    case portableDeclarative(page: PortableDeclarativePage, allowedHosts: [String])
    case media(URL)
    case anime
    case youtube
    case bilibili
    case nativeApp(bundleIdentifier: String)
}

public extension LaunchTarget {
    var isPortableApp: Bool {
        switch self {
        case .portableWeb, .portableDeclarative: true
        default: false
        }
    }

    var stableIdentity: String {
        switch self {
        case .web(let url):
            "web:\(url.absoluteString)"
        case let .portableWeb(entrypoint, _):
            "portable-web:\(entrypoint.absoluteString)"
        case let .portableDeclarative(page, _):
            "portable-declarative:\(page.title)"
        case .media(let url):
            "media:\(url.absoluteString)"
        case .anime:
            "anime"
        case .youtube:
            "youtube"
        case .bilibili:
            "bilibili"
        case .nativeApp(let bundleIdentifier):
            "native:\(bundleIdentifier)"
        }
    }
}

public struct TVAppProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var target: LaunchTarget
    public var controlMode: ControlMode
    public var isVisibleOnHome: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        target: LaunchTarget,
        controlMode: ControlMode,
        isVisibleOnHome: Bool = true
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.controlMode = controlMode
        self.isVisibleOnHome = isVisibleOnHome
    }
}

public enum ControlMode: String, Codable, Equatable, Sendable {
    case web
    case nativeKeyboard
    case nativeAccessibility
    case hybridNative
}

public enum ActiveRuntime: Equatable, Sendable {
    case launcher
    case web(TVAppProfile)
    case declarative(TVAppProfile)
    case media(TVAppProfile)
    case anime(TVAppProfile)
    case youtube(TVAppProfile)
    case bilibili(TVAppProfile)
    case native(TVAppProfile)
    case remoteLearning
    case settings
    case appManagement
    case animeSourceManagement
}

public extension Notification.Name {
    static let tvShellRuntimeCommand = Notification.Name("TVShellRuntimeCommand")
    static let tvShellRequestLauncher = Notification.Name("TVShellRequestLauncher")
    static let tvShellRecordWatch = Notification.Name("TVShellRecordWatch")
    static let tvShellRememberAnimeStream = Notification.Name("TVShellRememberAnimeStream")
    static let tvShellSetStatusClockHidden = Notification.Name("TVShellSetStatusClockHidden")
    static let tvShellRequestPortableAppImporter = Notification.Name("TVShellRequestPortableAppImporter")
}

public enum RuntimeCommandNotification {
    public static let commandKey = "command"
    public static let webModeKey = "webMode"
}

public enum WatchHistoryNotification {
    public static let entryKey = "entry"
}

public enum AnimeStreamPreferenceNotification {
    public static let mediaIDKey = "mediaID"
    public static let streamURLKey = "streamURL"
}

public enum StatusClockNotification {
    public static let hiddenKey = "hidden"
}
