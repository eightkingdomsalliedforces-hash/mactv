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

    public var navigationWidth: Double {
        switch kind {
        case .character:
            68
        case .space:
            150
        case .delete, .submit, .cancel, .layoutSwitch:
            132
        }
    }
}

public struct VirtualKeyboardState: Equatable, Sendable {
    public private(set) var text: String
    public private(set) var composition: String
    public private(set) var focusedRow: Int
    public private(set) var focusedColumn: Int
    public private(set) var focusedCandidateIndex: Int?
    public private(set) var layout: VirtualKeyboardLayout
    private var lastCompositionKey: String?

    public var candidates: [String] {
        ZhuyinComposer.candidates(for: composition)
    }

    public var visibleCandidates: [String] {
        Array(candidates.prefix(8))
    }

    public var isCandidateRowFocused: Bool {
        focusedCandidateIndex != nil
    }

    public var rows: [[VirtualKeyboardKey]] {
        Self.rows(for: layout)
    }

    public init(text: String = "", layout: VirtualKeyboardLayout = .latin) {
        self.text = text
        self.composition = ""
        self.focusedRow = 0
        self.focusedColumn = 0
        self.focusedCandidateIndex = nil
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
                ["ㄅ", "ㄉ", "ˇ", "ˋ", "ㄓ", "ˊ", "˙", "ㄚ", "ㄞ", "ㄢ", "ㄦ"].map { VirtualKeyboardKey($0) },
                ["ㄆ", "ㄊ", "ㄍ", "ㄐ", "ㄔ", "ㄗ", "ㄧ", "ㄛ", "ㄟ", "ㄣ"].map { VirtualKeyboardKey($0) },
                ["ㄇ", "ㄋ", "ㄎ", "ㄑ", "ㄕ", "ㄘ", "ㄨ", "ㄜ", "ㄠ", "ㄤ"].map { VirtualKeyboardKey($0) },
                ["ㄈ", "ㄌ", "ㄏ", "ㄒ", "ㄖ", "ㄙ", "ㄩ", "ㄝ", "ㄡ", "ㄥ"].map { VirtualKeyboardKey($0) },
                [
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
            if let index = focusedCandidateIndex {
                focusedCandidateIndex = max(0, index - 1)
            } else {
                focusedColumn = max(0, focusedColumn - 1)
            }
            return .none
        case .right:
            if let index = focusedCandidateIndex {
                focusedCandidateIndex = min(max(visibleCandidates.count - 1, 0), index + 1)
            } else {
                focusedColumn = min(rows[focusedRow].count - 1, focusedColumn + 1)
            }
            return .none
        case .up:
            if let index = focusedCandidateIndex {
                focusedCandidateIndex = max(0, index - 1)
            } else if shouldEnterCandidateRow {
                focusedCandidateIndex = min(focusedColumn, visibleCandidates.count - 1)
            } else {
                moveFocus(toRow: max(0, focusedRow - 1))
            }
            return .none
        case .down:
            if let index = focusedCandidateIndex {
                focusedColumn = min(index, rows[focusedRow].count - 1)
                focusedCandidateIndex = nil
            } else {
                moveFocus(toRow: min(rows.count - 1, focusedRow + 1))
            }
            return .none
        case .back:
            if composition.isEmpty == false {
                composition.removeLast()
                lastCompositionKey = nil
                focusedCandidateIndex = nil
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
        if let focusedCandidateIndex,
           visibleCandidates.indices.contains(focusedCandidateIndex) {
            commit(visibleCandidates[focusedCandidateIndex])
            return .textChanged
        }

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
                    focusedCandidateIndex = nil
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
                focusedCandidateIndex = nil
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
            focusedCandidateIndex = nil
            focusedRow = 0
            focusedColumn = 0
            return .none
        }
    }

    private mutating func moveFocus(toRow destinationRow: Int) {
        guard destinationRow != focusedRow else { return }
        let sourceCenter = keyCenter(in: rows[focusedRow], at: focusedColumn)
        let destination = rows[destinationRow]
        focusedRow = destinationRow
        focusedColumn = destination.indices.min { left, right in
            abs(keyCenter(in: destination, at: left) - sourceCenter)
                < abs(keyCenter(in: destination, at: right) - sourceCenter)
        } ?? 0
    }

    private func keyCenter(in row: [VirtualKeyboardKey], at index: Int) -> Double {
        let spacing = 12.0
        let leadingWidth = row.prefix(index).reduce(0) { $0 + $1.navigationWidth }
        return leadingWidth + (Double(index) * spacing) + (row[index].navigationWidth / 2)
    }

    private var shouldEnterCandidateRow: Bool {
        layout == .zhuyin
            && composition.isEmpty == false
            && visibleCandidates.isEmpty == false
            && focusedRow == 0
    }

    private mutating func commit(_ value: String) {
        text += value
        composition = ""
        lastCompositionKey = nil
        focusedCandidateIndex = nil
    }

    public mutating func typeZhuyinForTesting(_ value: String) {
        composition = value
        lastCompositionKey = focusedKey.label
        focusedCandidateIndex = nil
    }
}

public enum ZhuyinComposer {
    private static let curatedDictionary: [String: [String]] = [
        "ㄅ": ["不", "ㄅ"],
        "ㄆ": ["片", "ㄆ"],
        "ㄇ": ["嗎", "魔", "ㄇ"],
        "ㄈ": ["非", "ㄈ"],
        "ㄧ": ["一"],
        "ㄨㄛˇ": ["我"],
        "ㄋㄧˇ": ["你"],
        "ㄊㄚ": ["他", "她", "它"],
        "ㄕˋ": ["是", "事", "市", "式"],
        "ㄧㄡˇ": ["有"],
        "ㄗㄞˋ": ["在", "再"],
        "ㄅㄨˋ": ["不"],
        "ㄓㄜˋ": ["這"],
        "ㄌㄜ˙": ["了"],
        "ㄧˇ": ["以", "已"],
        "ㄉㄚˋ": ["大"],
        "ㄒㄧㄠˇ": ["小"],
        "ㄍㄜˋ": ["個"],
        "ㄏㄨㄟˋ": ["會"],
        "ㄨㄟˋ": ["為", "位"],
        "ㄌㄞˊ": ["來"],
        "ㄐㄧㄡˋ": ["就"],
        "ㄉㄠˋ": ["到", "道"],
        "ㄧㄠˋ": ["要"],
        "ㄧㄡˋ": ["又"],
        "ㄑㄩˋ": ["去"],
        "ㄏㄠˇ": ["好"],
        "ㄇㄟˊ": ["沒"],
        "ㄏㄣˇ": ["很"],
        "ㄉㄨㄛ": ["多"],
        "ㄕㄠˇ": ["少"],
        "ㄎㄢˋ": ["看"],
        "ㄊㄧㄥ": ["聽"],
        "ㄕㄨㄛ": ["說"],
        "ㄒㄧㄤˇ": ["想"],
        "ㄔ": ["吃"],
        "ㄏㄜ": ["喝"],
        "ㄇㄞˇ": ["買"],
        "ㄇㄞˋ": ["賣"],
        "ㄕㄨㄟˇ": ["水"],
        "ㄏㄨㄛˇ": ["火"],
        "ㄕㄢ": ["山"],
        "ㄖˋ": ["日"],
        "ㄩㄝˋ": ["月"],
        "ㄋㄧㄢˊ": ["年"],
        "ㄊㄧㄢ": ["天"],
        "ㄇㄧㄥˊ": ["名", "明"],
        "ㄗˋ": ["字"],
        "ㄑㄧㄥˇ": ["請"],
        "ㄒㄧㄝˋ": ["謝"],
        "ㄌㄠˇ": ["老"],
        "ㄕ": ["師"],
        "ㄌㄠˇㄕ": ["老師"],
        "ㄒㄩㄝˊㄕㄥ": ["學生"],
        "ㄨㄤˇ": ["網"],
        "ㄌㄨˋ": ["路"],
        "ㄨㄤˇㄌㄨˋ": ["網路"],
        "ㄩㄢˊ": ["源", "員", "原"],
        "ㄓㄨˇ": ["主"],
        "ㄧㄝˇ": ["也"],
        "ㄎㄜˇ": ["可"],
        "ㄎㄚˇ": ["卡"],
        "ㄇㄚˇ": ["馬"],
        "ㄋㄚˋ": ["那", "娜"],
        "ㄧㄚˋ": ["亞"],
        "ㄌㄧˇ": ["里", "理"],
        "ㄞˋ": ["愛"],
        "ㄌㄧˊ": ["梨"],
        "ㄉㄜ": ["的"],
        "ㄉㄜ˙": ["的"],
        "ㄕˊ": ["時"],
        "ㄑㄧㄥ": ["輕"],
        "ㄕㄥ": ["聲"],
        "ㄜˊ": ["俄"],
        "ㄩˇ": ["語"],
        "ㄉㄧㄢˋ": ["電", "店"],
        "ㄉㄧㄢˇ": ["點"],
        "ㄋㄠˇ": ["腦"],
        "ㄧㄥˇ": ["影"],
        "ㄉㄧㄢˋㄋㄠˇ": ["電腦"],
        "ㄉㄧㄢˋㄧㄥˇ": ["電影"],
        "ㄓㄜ": ["遮"],
        "ㄒㄧㄡ": ["羞"],
        "ㄌㄧㄣˊ": ["鄰"],
        "ㄗㄨㄛˋ": ["座"],
        "ㄊㄨㄥˊ": ["同"],
        "ㄒㄩㄝˊ": ["學"],
        "ㄓㄨˋ": ["注", "住"],
        "ㄧㄣ": ["音"],
        "ㄓㄨˋㄧㄣ": ["注音"],
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

    private static let dictionary = mergeDictionaries(
        curatedDictionary,
        ZhuyinChewingDictionary.candidates
    )

    private static let aliases: [String: String] = [
        "ㄎㄧㄚˇ": "ㄎㄚˇ"
    ]

    private static func mergeDictionaries(_ preferred: [String: [String]], _ fallback: [String: [String]]) -> [String: [String]] {
        var merged = fallback
        for (key, values) in preferred {
            var uniqueValues: [String] = []
            for value in values + (merged[key] ?? []) where uniqueValues.contains(value) == false {
                uniqueValues.append(value)
            }
            merged[key] = Array(uniqueValues.prefix(10))
        }
        return merged
    }

    public static func candidates(for composition: String) -> [String] {
        guard composition.isEmpty == false else { return [] }
        if let exact = dictionary[composition] {
            return exact
        }
        let normalized = aliases[composition] ?? composition
        if let exact = dictionary[normalized] {
            return exact
        }

        let segmented = segmentedCandidates(for: normalized)
        if segmented.isEmpty == false {
            return segmented
        }

        let matches = dictionary
            .filter { key, _ in
                key.hasPrefix(composition)
                    || composition.hasPrefix(key)
                    || key.hasPrefix(normalized)
                    || normalized.hasPrefix(key)
            }
            .flatMap(\.value)
        if matches.isEmpty == false {
            return Array(matches.prefix(8))
        }
        return [composition]
    }

    private static func segmentedCandidates(for composition: String) -> [String] {
        var remaining = composition
        var syllables: [[String]] = []

        while remaining.isEmpty == false {
            let match = dictionary.keys
                .filter { remaining.hasPrefix($0) }
                .sorted { left, right in
                    if left.count == right.count {
                        return left < right
                    }
                    return left.count > right.count
                }
                .first

            guard let match, let values = dictionary[match] else {
                return []
            }

            syllables.append(Array(values.prefix(2)))
            remaining.removeFirst(match.count)
        }

        guard syllables.count > 1 else {
            return []
        }

        let primary = syllables.compactMap(\.first).joined()
        let secondary = syllables.map { values in values.dropFirst().first ?? values.first ?? "" }.joined()
        if secondary.isEmpty || secondary == primary {
            return [primary]
        }
        return [primary, secondary]
    }
}
