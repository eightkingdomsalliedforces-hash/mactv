import Foundation

public enum VirtualKeyboardAction: Equatable, Sendable {
    case none
    case textChanged
    case submitted(String)
    case cancelled
}

public enum VirtualKeyboardLayout: String, Codable, Equatable, Sendable {
    case latin
    case zhuyin

    public var title: String {
        switch self {
        case .latin: "ABC"
        case .zhuyin: "注音"
        }
    }
}

public struct VirtualKeyboardKey: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public var label: String
    public var value: String?
    public var kind: Kind

    public enum Kind: Equatable, Sendable {
        case character
        case space
        case delete
        case submit
        case cancel
        case layoutSwitch
    }

    public init(_ label: String, value: String? = nil, kind: Kind = .character) {
        self.label = label
        self.value = value
        self.kind = kind
    }
}

public struct VirtualKeyboardState: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var focusedRow: Int
    public private(set) var focusedColumn: Int
    public private(set) var layout: VirtualKeyboardLayout
    public var rows: [[VirtualKeyboardKey]] {
        Self.rows(for: layout)
    }

    public init(text: String = "", layout: VirtualKeyboardLayout = .latin) {
        self.text = text
        self.focusedRow = 0
        self.focusedColumn = 0
        self.layout = layout
    }

    private static func rows(for layout: VirtualKeyboardLayout) -> [[VirtualKeyboardKey]] {
        switch layout {
        case .latin:
            return [
            "1234567890".map { VirtualKeyboardKey(String($0)) },
            "QWERTYUIOP".map { VirtualKeyboardKey(String($0)) },
            "ASDFGHJKL".map { VirtualKeyboardKey(String($0)) },
            "ZXCVBNM".map { VirtualKeyboardKey(String($0)) },
            [
                VirtualKeyboardKey("空格", value: " ", kind: .space),
                VirtualKeyboardKey("刪除", kind: .delete),
                VirtualKeyboardKey("搜尋", kind: .submit),
                VirtualKeyboardKey("注音", kind: .layoutSwitch),
                VirtualKeyboardKey("取消", kind: .cancel)
            ]
            ]
        case .zhuyin:
            return [
                "ㄅㄆㄇㄈㄉㄊㄋㄌ".map { VirtualKeyboardKey(String($0)) },
                "ㄍㄎㄏㄐㄑㄒ".map { VirtualKeyboardKey(String($0)) },
                "ㄓㄔㄕㄖㄗㄘㄙ".map { VirtualKeyboardKey(String($0)) },
                "ㄧㄨㄩㄚㄛㄜㄝ".map { VirtualKeyboardKey(String($0)) },
                "ㄞㄟㄠㄡㄢㄣㄤㄥㄦ".map { VirtualKeyboardKey(String($0)) },
                [
                    VirtualKeyboardKey("ˊ"),
                    VirtualKeyboardKey("ˇ"),
                    VirtualKeyboardKey("ˋ"),
                    VirtualKeyboardKey("˙"),
                    VirtualKeyboardKey("空格", value: " ", kind: .space),
                    VirtualKeyboardKey("刪除", kind: .delete),
                    VirtualKeyboardKey("搜尋", kind: .submit),
                    VirtualKeyboardKey("ABC", kind: .layoutSwitch),
                    VirtualKeyboardKey("取消", kind: .cancel)
                ]
            ]
        }
    }

    public var focusedKey: VirtualKeyboardKey {
        rows[focusedRow][focusedColumn]
    }

    public mutating func apply(_ command: RemoteCommand) -> VirtualKeyboardAction {
        switch command {
        case .left:
            focusedColumn = max(0, focusedColumn - 1)
            return .none
        case .right:
            focusedColumn = min(rows[focusedRow].count - 1, focusedColumn + 1)
            return .none
        case .up:
            focusedRow = max(0, focusedRow - 1)
            focusedColumn = min(focusedColumn, rows[focusedRow].count - 1)
            return .none
        case .down:
            focusedRow = min(rows.count - 1, focusedRow + 1)
            focusedColumn = min(focusedColumn, rows[focusedRow].count - 1)
            return .none
        case .back:
            if text.isEmpty {
                return .cancelled
            }
            text.removeLast()
            return .textChanged
        case .select:
            return activateFocusedKey()
        default:
            return .none
        }
    }

    private mutating func activateFocusedKey() -> VirtualKeyboardAction {
        let key = focusedKey
        switch key.kind {
        case .character, .space:
            text += key.value ?? key.label
            return .textChanged
        case .delete:
            if text.isEmpty == false {
                text.removeLast()
            }
            return .textChanged
        case .submit:
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? .none : .submitted(query)
        case .cancel:
            return .cancelled
        case .layoutSwitch:
            layout = layout == .latin ? .zhuyin : .latin
            focusedRow = min(focusedRow, rows.count - 1)
            focusedColumn = min(focusedColumn, rows[focusedRow].count - 1)
            return .none
        }
    }
}
