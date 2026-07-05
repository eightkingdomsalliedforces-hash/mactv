public struct KeyCodeMapper: Equatable, Sendable {
    public static let `default` = KeyCodeMapper()

    public init() {}

    public func command(for event: RawInputEvent) -> RemoteCommand? {
        switch event {
        case let .keyboard(keyCode, characters, modifiers):
            commandForKeyboard(keyCode: keyCode, characters: characters, modifiers: modifiers)
        case let .media(systemCode):
            commandForMedia(systemCode: systemCode)
        case let .hid(usagePage, usage):
            commandForHID(usagePage: usagePage, usage: usage)
        }
    }

    private func commandForKeyboard(
        keyCode: UInt16,
        characters: String?,
        modifiers: Set<RemoteModifier>
    ) -> RemoteCommand? {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 36, 76: return .select
        case 53: return .back
        case 49: return .playPause
        case 4 where modifiers.contains(.command): return .home
        case 46 where modifiers.contains(.command): return .menu
        default:
            if characters == "\r" { return .select }
            if characters == "\u{1b}" { return .back }
            return nil
        }
    }

    private func commandForMedia(systemCode: Int) -> RemoteCommand? {
        switch systemCode {
        case 16: return .playPause
        case 17, 19: return .fastForward
        case 18, 20: return .rewind
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        default: return nil
        }
    }

    private func commandForHID(usagePage: Int, usage: Int) -> RemoteCommand? {
        if usagePage == 0x0C {
            switch usage {
            case 0x40: return .menu
            case 0x41: return .select
            case 0xCD: return .playPause
            case 0xB3: return .fastForward
            case 0xB4: return .rewind
            case 0xE9: return .volumeUp
            case 0xEA: return .volumeDown
            case 0xE2: return .mute
            case 0x223: return .home
            case 0x224: return .back
            default: return nil
            }
        }

        return nil
    }
}
