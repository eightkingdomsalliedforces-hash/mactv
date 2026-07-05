public struct MediaControlState: Equatable, Sendable {
    public private(set) var isPlaying: Bool
    public private(set) var pendingSeekOffset: Double
    public private(set) var shouldExit: Bool

    public init(isPlaying: Bool = false, pendingSeekOffset: Double = 0, shouldExit: Bool = false) {
        self.isPlaying = isPlaying
        self.pendingSeekOffset = pendingSeekOffset
        self.shouldExit = shouldExit
    }

    public mutating func apply(_ command: RemoteCommand) {
        pendingSeekOffset = 0

        switch command {
        case .playPause, .select:
            isPlaying.toggle()
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
