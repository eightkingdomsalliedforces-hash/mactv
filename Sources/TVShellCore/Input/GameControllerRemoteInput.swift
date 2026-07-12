import Foundation

public enum GameControllerRemoteButton: String, Sendable {
    case up
    case down
    case left
    case right
    case primary
    case back
    case home
    case menu
    case playPause
}

public enum GameControllerRemoteInput {
    public static func rawInput(for button: GameControllerRemoteButton) -> RawInputEvent {
        switch button {
        case .up: .hid(usagePage: 0x01, usage: 0x90)
        case .down: .hid(usagePage: 0x01, usage: 0x91)
        case .right: .hid(usagePage: 0x01, usage: 0x92)
        case .left: .hid(usagePage: 0x01, usage: 0x93)
        case .primary: .hid(usagePage: 0x0C, usage: 0x41)
        case .back: .hid(usagePage: 0x0C, usage: 0x224)
        case .home: .hid(usagePage: 0x0C, usage: 0x223)
        case .menu: .hid(usagePage: 0x0C, usage: 0x40)
        case .playPause: .hid(usagePage: 0x0C, usage: 0xCD)
        }
    }
}
