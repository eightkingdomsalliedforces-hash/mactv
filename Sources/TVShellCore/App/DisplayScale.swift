public enum DisplayScale: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case percent100
    case percent125
    case percent150
    case percent200

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .percent100: "100%"
        case .percent125: "125%"
        case .percent150: "150%"
        case .percent200: "200%"
        }
    }

    public func multiplier(forScreenScale screenScale: Double = 1.0) -> Double {
        switch self {
        case .auto:
            screenScale >= 2.0 ? 1.5 : 1.0
        case .percent100:
            1.0
        case .percent125:
            1.25
        case .percent150:
            1.5
        case .percent200:
            2.0
        }
    }

    public var next: DisplayScale {
        switch self {
        case .auto: .percent100
        case .percent100: .percent125
        case .percent125: .percent150
        case .percent150: .percent200
        case .percent200: .auto
        }
    }

    public var previous: DisplayScale {
        switch self {
        case .auto: .percent200
        case .percent100: .auto
        case .percent125: .percent100
        case .percent150: .percent125
        case .percent200: .percent150
        }
    }
}
