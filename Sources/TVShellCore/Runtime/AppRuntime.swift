import Foundation

public enum RuntimeKind: String, Codable, Equatable, Sendable {
    case launcher
    case web
    case native
    case remoteLearning
}

public enum LaunchTarget: Equatable, Codable, Sendable {
    case web(URL)
    case media(URL)
    case anime
    case youtube
    case nativeApp(bundleIdentifier: String)
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
    case media(TVAppProfile)
    case anime(TVAppProfile)
    case youtube(TVAppProfile)
    case native(TVAppProfile)
    case remoteLearning
    case settings
    case appManagement
    case animeSourceManagement
}

public extension Notification.Name {
    static let tvShellRuntimeCommand = Notification.Name("TVShellRuntimeCommand")
    static let tvShellRequestLauncher = Notification.Name("TVShellRequestLauncher")
}

public enum RuntimeCommandNotification {
    public static let commandKey = "command"
    public static let webModeKey = "webMode"
}
