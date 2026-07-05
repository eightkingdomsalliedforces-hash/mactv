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
    case nativeApp(bundleIdentifier: String)
}

public struct TVAppProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var target: LaunchTarget
    public var controlMode: ControlMode

    public init(
        id: UUID = UUID(),
        name: String,
        target: LaunchTarget,
        controlMode: ControlMode
    ) {
        self.id = id
        self.name = name
        self.target = target
        self.controlMode = controlMode
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
    case native(TVAppProfile)
    case remoteLearning
    case settings
}

public extension Notification.Name {
    static let tvShellRuntimeCommand = Notification.Name("TVShellRuntimeCommand")
}

public enum RuntimeCommandNotification {
    public static let commandKey = "command"
}
