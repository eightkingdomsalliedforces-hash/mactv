public enum RemoteModifier: String, Codable, Equatable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public enum RawInputEvent: Equatable, Hashable, Codable, Sendable {
    case keyboard(keyCode: UInt16, characters: String?, modifiers: Set<RemoteModifier>)
    case media(systemCode: Int)
    case hid(usagePage: Int, usage: Int)
}
