public struct MediaControlState: Equatable, Sendable {
    public private(set) var isPlaying: Bool
    public private(set) var pendingSeekOffset: Double
    public private(set) var shouldRestartFromBeginning: Bool
    public private(set) var shouldExit: Bool

    public init(
        isPlaying: Bool = false,
        pendingSeekOffset: Double = 0,
        shouldRestartFromBeginning: Bool = false,
        shouldExit: Bool = false
    ) {
        self.isPlaying = isPlaying
        self.pendingSeekOffset = pendingSeekOffset
        self.shouldRestartFromBeginning = shouldRestartFromBeginning
        self.shouldExit = shouldExit
    }

    public mutating func apply(_ command: RemoteCommand) {
        pendingSeekOffset = 0
        shouldRestartFromBeginning = false

        switch command {
        case .playPause:
            isPlaying.toggle()
        case .select:
            shouldRestartFromBeginning = true
            isPlaying = true
        case .left, .rewind:
            pendingSeekOffset = -10
        case .right, .fastForward:
            pendingSeekOffset = 10
        case .back, .home:
            shouldExit = true
        default:
            break
        }
    }
}
