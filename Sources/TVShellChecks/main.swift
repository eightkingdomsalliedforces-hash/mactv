import CoreGraphics
import Foundation
import TVShellCore

@main
struct TVShellChecks {
    static func main() throws {
        try checkKeyCodeMapper()
        try checkRemoteMappingStore()
        try checkFocusEngine()
        print("TVShellChecks passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw CheckFailure(message)
        }
    }

    static func checkKeyCodeMapper() throws {
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 126, characters: nil, modifiers: [])) == .up, "up arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 125, characters: nil, modifiers: [])) == .down, "down arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 123, characters: nil, modifiers: [])) == .left, "left arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 124, characters: nil, modifiers: [])) == .right, "right arrow maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 36, characters: "\r", modifiers: [])) == .select, "return maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 53, characters: "\u{1b}", modifiers: [])) == .back, "escape maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 4, characters: "h", modifiers: [.command])) == .home, "command-h maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 49, characters: " ", modifiers: [])) == .playPause, "space maps")
        try expect(KeyCodeMapper.default.command(for: .keyboard(keyCode: 8, characters: "c", modifiers: [])) == nil, "unknown remains nil")
    }

    static func checkRemoteMappingStore() throws {
        var store = RemoteMappingStore()
        let raw = RawInputEvent.keyboard(keyCode: 8, characters: "c", modifiers: [])

        try expect(store.command(for: raw) == nil, "unknown command before learning")
        store.learn(raw, as: .home)
        try expect(store.command(for: raw) == .home, "learned mapping overrides unknown input")

        let hid = RawInputEvent.hid(usagePage: 12, usage: 999)
        store.learn(hid, as: .back)
        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(RemoteMappingStore.self, from: data)
        try expect(decoded.command(for: hid) == .back, "mappings round-trip through JSON")
    }

    static func checkFocusEngine() throws {
        var engine = FocusEngine()
        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 140, y: 180, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")
        try expect(engine.move(.right) == "b", "right moves to nearest same row candidate")

        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 20, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 280, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")
        try expect(engine.move(.down) == "b", "down moves to nearest vertical candidate")

        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 1, acceptsSelect: true)
        ])
        try expect(engine.recoverFocus(in: "home") == "b", "recover chooses highest-priority visible node")
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
