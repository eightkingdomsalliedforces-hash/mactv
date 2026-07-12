public struct AnimeSourceNavigationState: Equatable, Sendable {
    public private(set) var focusedSourceIndex: Int
    public private(set) var isNavigationFocused: Bool
    private let sourceCount: Int

    public init(sourceCount: Int, focusedSourceIndex: Int = 0, isNavigationFocused: Bool = true) {
        self.sourceCount = max(0, sourceCount)
        self.focusedSourceIndex = min(max(0, focusedSourceIndex), max(sourceCount - 1, 0))
        self.isNavigationFocused = isNavigationFocused
    }

    public mutating func move(_ command: RemoteCommand) {
        guard isNavigationFocused else { return }
        switch command {
        case .left:
            focusedSourceIndex = max(0, focusedSourceIndex - 1)
        case .right:
            focusedSourceIndex = min(max(sourceCount - 1, 0), focusedSourceIndex + 1)
        default:
            break
        }
    }

    public mutating func enterContent() {
        isNavigationFocused = false
    }

    public mutating func enterNavigation() {
        isNavigationFocused = true
    }
}

public enum AnimeMainTab: String, CaseIterable, Equatable, Sendable {
    case recommended
    case official
    case subscriptions
    case history
    case search

    public var title: String {
        switch self {
        case .recommended: "推薦"
        case .official: "正版來源"
        case .subscriptions: "我的訂閱"
        case .history: "觀看記錄"
        case .search: "搜尋"
        }
    }

    public var symbolName: String? {
        self == .search ? "magnifyingglass" : nil
    }
}
