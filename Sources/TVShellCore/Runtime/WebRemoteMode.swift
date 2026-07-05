public enum WebRemoteMode: String, Codable, Equatable, Sendable {
    case keyboard
    case domFocus
    case scroll
    case mouse

    public var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .domFocus: "DOM Focus"
        case .scroll: "Scroll"
        case .mouse: "Mouse"
        }
    }

    public var next: WebRemoteMode {
        switch self {
        case .keyboard: .domFocus
        case .domFocus: .scroll
        case .scroll: .mouse
        case .mouse: .keyboard
        }
    }
}
