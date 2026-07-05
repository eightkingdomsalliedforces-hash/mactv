import AppKit

public enum AppKitRemoteEventTranslator {
    public static func rawInput(from event: NSEvent) -> RawInputEvent? {
        switch event.type {
        case .keyDown:
            return .keyboard(
                keyCode: event.keyCode,
                characters: event.characters,
                modifiers: RemoteModifier.from(event.modifierFlags)
            )
        case .systemDefined:
            return mediaInput(from: event)
        default:
            return nil
        }
    }

    private static func mediaInput(from event: NSEvent) -> RawInputEvent? {
        guard event.subtype.rawValue == 8 else {
            return nil
        }

        let keyCode = Int((event.data1 & 0xFFFF_0000) >> 16)
        let keyState = Int((event.data1 & 0x0000_FF00) >> 8)

        guard keyState == 0x0A else {
            return nil
        }

        return .media(systemCode: keyCode)
    }
}
