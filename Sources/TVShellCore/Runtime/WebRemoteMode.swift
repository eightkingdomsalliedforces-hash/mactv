public enum WebRemoteMode: String, Codable, Equatable, Sendable {
    case keyboard
    case domFocus
    case scroll

    public var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .domFocus: "DOM Focus"
        case .scroll: "Scroll"
        }
    }

    public var next: WebRemoteMode {
        switch self {
        case .keyboard: .domFocus
        case .domFocus: .scroll
        case .scroll: .keyboard
        }
    }
}
