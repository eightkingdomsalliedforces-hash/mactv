import Foundation

public enum PortableAppRuntimeKind: String, Codable, Equatable, Sendable {
    case web
    case declarative
}

public enum PortableDeclarativeActionKind: String, Codable, Equatable, Sendable {
    case status
    case openURL
}

public struct PortableDeclarativeAction: Codable, Equatable, Sendable {
    public var kind: PortableDeclarativeActionKind
    public var value: String

    public init(kind: PortableDeclarativeActionKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct PortableDeclarativeCard: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var action: PortableDeclarativeAction

    public init(id: String, title: String, subtitle: String? = nil, action: PortableDeclarativeAction) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }
}

public struct PortableDeclarativeSection: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var cards: [PortableDeclarativeCard]

    public init(id: String, title: String, cards: [PortableDeclarativeCard]) {
        self.id = id
        self.title = title
        self.cards = cards
    }
}

public struct PortableDeclarativePage: Codable, Equatable, Sendable {
    public var title: String
    public var sections: [PortableDeclarativeSection]

    public init(title: String, sections: [PortableDeclarativeSection]) {
        self.title = title
        self.sections = sections
    }

    public var cards: [PortableDeclarativeCard] {
        sections.flatMap(\.cards)
    }

    func validate(allowedHosts: [String]) throws {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              sections.isEmpty == false,
              sections.count <= 20,
              cards.isEmpty == false,
              cards.count <= 200
        else {
            throw PortableAppPackageError.invalidManifest("宣告 UI 必須包含標題與 1...200 張卡片")
        }
        let sectionIDs = sections.map(\.id)
        let cardIDs = cards.map(\.id)
        guard Set(sectionIDs).count == sectionIDs.count,
              Set(cardIDs).count == cardIDs.count,
              (sectionIDs + cardIDs).allSatisfy({
                  $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil
              })
        else {
            throw PortableAppPackageError.invalidManifest("宣告 UI 的 section/card id 必須唯一且格式有效")
        }
        for card in cards {
            guard card.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  card.action.value.count <= 2_048
            else {
                throw PortableAppPackageError.invalidManifest("宣告 UI 卡片標題不可留空")
            }
            if card.action.kind == .openURL {
                guard let url = URL(string: card.action.value),
                      url.scheme?.lowercased() == "https",
                      let host = url.host?.lowercased(),
                      allowedHosts.map({ $0.lowercased() }).contains(host)
                else {
                    throw PortableAppPackageError.invalidManifest("宣告 UI 的 openURL 必須是 allowedHosts 內的 HTTPS 網址")
                }
            }
        }
    }
}

public struct PortableDeclarativeRuntimeState: Equatable, Sendable {
    public private(set) var focusedIndex = 0
    public private(set) var statusText: String
    public let page: PortableDeclarativePage

    public init(page: PortableDeclarativePage) {
        self.page = page
        statusText = page.title
    }

    public var focusedCard: PortableDeclarativeCard? {
        page.cards.indices.contains(focusedIndex) ? page.cards[focusedIndex] : nil
    }

    public mutating func apply(_ command: RemoteCommand, columns: Int = 4) {
        let count = page.cards.count
        switch command {
        case .left: focusedIndex = max(0, focusedIndex - 1)
        case .right: focusedIndex = min(max(count - 1, 0), focusedIndex + 1)
        case .up: focusedIndex = max(0, focusedIndex - max(columns, 1))
        case .down: focusedIndex = min(max(count - 1, 0), focusedIndex + max(columns, 1))
        case .select:
            guard let card = focusedCard else { return }
            statusText = card.action.kind == .status ? card.action.value : "正在開啟：\(card.title)"
        default: break
        }
    }
}
