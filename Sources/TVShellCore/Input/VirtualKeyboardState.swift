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
    public private(set) var composition: String
    public private(set) var focusedRow: Int
    public private(set) var focusedColumn: Int
    public private(set) var layout: VirtualKeyboardLayout
    private var lastCompositionKey: String?

    public var candidates: [String] {
        ZhuyinComposer.candidates(for: composition)
    }

    public var rows: [[VirtualKeyboardKey]] {
        Self.rows(for: layout)
    }

    public init(text: String = "", layout: VirtualKeyboardLayout = .latin) {
        self.text = text
        self.composition = ""
        self.focusedRow = 0
        self.focusedColumn = 0
        self.layout = layout
        self.lastCompositionKey = nil
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
            if composition.isEmpty == false {
                composition.removeLast()
                lastCompositionKey = nil
                return .textChanged
            }
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
        case .character:
            if layout == .zhuyin {
                if composition.isEmpty == false,
                   key.label == lastCompositionKey,
                   let candidate = candidates.first {
                    commit(candidate)
                } else {
                    composition += key.value ?? key.label
                    lastCompositionKey = key.label
                }
                return .textChanged
            }
            text += key.value ?? key.label
            return .textChanged
        case .space:
            if layout == .zhuyin, composition.isEmpty == false {
                commit(candidates.first ?? composition)
            } else {
                text += key.value ?? key.label
            }
            return .textChanged
        case .delete:
            if composition.isEmpty == false {
                composition.removeLast()
                lastCompositionKey = nil
            } else if text.isEmpty == false {
                text.removeLast()
            }
            return .textChanged
        case .submit:
            if composition.isEmpty == false {
                commit(candidates.first ?? composition)
            }
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? .none : .submitted(query)
        case .cancel:
            return .cancelled
        case .layoutSwitch:
            layout = layout == .latin ? .zhuyin : .latin
            composition = ""
            lastCompositionKey = nil
            focusedRow = min(focusedRow, rows.count - 1)
            focusedColumn = min(focusedColumn, rows[focusedRow].count - 1)
            return .none
        }
    }

    private mutating func commit(_ value: String) {
        text += value
        composition = ""
        lastCompositionKey = nil
    }

    public mutating func typeZhuyinForTesting(_ value: String) {
        composition = value
        lastCompositionKey = focusedKey.label
    }
}

public enum ZhuyinComposer {
    private static let dictionary: [String: [String]] = [
        "ㄅ": ["不", "ㄅ"],
        "ㄆ": ["片", "ㄆ"],
        "ㄇ": ["嗎", "魔", "ㄇ"],
        "ㄈ": ["非", "ㄈ"],
        "ㄎㄜˇ": ["可"],
        "ㄎㄚˇ": ["卡"],
        "ㄇㄚˇ": ["馬"],
        "ㄋㄚˋ": ["娜"],
        "ㄧㄚˋ": ["亞"],
        "ㄌㄧˇ": ["里", "理"],
        "ㄞˋ": ["愛"],
        "ㄌㄧˊ": ["梨"],
        "ㄎㄜˇㄎㄜˇ": ["可可"],
        "ㄈㄨˊ": ["芙", "福", "服"],
        "ㄌㄧˋ": ["莉", "麗", "力"],
        "ㄌㄧㄢˊ": ["蓮", "連"],
        "ㄈㄨˊㄌㄧˋㄌㄧㄢˊ": ["芙莉蓮"],
        "ㄉㄨㄥˋ": ["動"],
        "ㄇㄢˋ": ["漫"],
        "ㄉㄨㄥˋㄇㄢˋ": ["動漫"],
        "ㄓㄨㄥ": ["中"],
        "ㄨㄣˊ": ["文"],
        "ㄓㄨㄥㄨㄣˊ": ["中文"],
        "ㄖㄣˊ": ["人"],
        "ㄐㄧㄣˋ": ["進"],
        "ㄐㄧˊ": ["擊"],
        "ㄐㄧㄣˋㄐㄧˊ": ["進擊"],
        "ㄍㄨㄟˇ": ["鬼"],
        "ㄇㄧㄝˋ": ["滅"],
        "ㄖㄣˋ": ["刃"],
        "ㄍㄨㄟˇㄇㄧㄝˋㄓㄖㄣˋ": ["鬼滅之刃"],
        "ㄆㄞˊ": ["排"],
        "ㄑㄧㄡˊ": ["球"],
        "ㄆㄞˊㄑㄧㄡˊ": ["排球"],
        "ㄓㄡˋ": ["咒"],
        "ㄕㄨˋ": ["術"],
        "ㄏㄨㄟˊ": ["迴"],
        "ㄓㄢˋ": ["戰"],
        "ㄓㄡˋㄕㄨˋㄏㄨㄟˊㄓㄢˋ": ["咒術迴戰"]
    ]

    public static func candidates(for composition: String) -> [String] {
        guard composition.isEmpty == false else { return [] }
        if let exact = dictionary[composition] {
            return exact
        }

        let matches = dictionary
            .filter { key, _ in key.hasPrefix(composition) || composition.hasPrefix(key) }
            .flatMap(\.value)
        if matches.isEmpty == false {
            return Array(matches.prefix(8))
        }
        return [composition]
    }
}
