import Foundation

public enum AnimeSourceHealth: String, Codable, Equatable, Sendable {
    case loading
    case available
    case failed
    case needsCloudflare
    case needsCaptcha
    case needsAdapter
    case disabled
}

public enum AnimeSourceDisplayMode: String, Codable, Equatable, Sendable {
    case simple
    case detailed

    public var next: AnimeSourceDisplayMode {
        switch self {
        case .simple: .detailed
        case .detailed: .simple
        }
    }
}

public struct AnimeSourceLine: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let isDeprecated: Bool

    public init(id: String, title: String, isDeprecated: Bool = false) {
        self.id = id
        self.title = title
        self.isDeprecated = isDeprecated
    }
}

public struct AnimeSourceDefinition: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let iconLabel: String
    public let lines: [AnimeSourceLine]
    public let health: AnimeSourceHealth
    public let defaultEnabled: Bool
    public let isAdult: Bool

    public init(
        id: String,
        title: String,
        iconLabel: String,
        lines: [AnimeSourceLine],
        health: AnimeSourceHealth = .available,
        defaultEnabled: Bool = true,
        isAdult: Bool = false
    ) {
        self.id = id
        self.title = title
        self.iconLabel = iconLabel
        self.lines = lines
        self.health = health
        self.defaultEnabled = defaultEnabled
        self.isAdult = isAdult
    }
}

public struct AnimeSourceInstance: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var definition: AnimeSourceDefinition
    public var isEnabled: Bool
    public var selectedLineID: String?

    public init(definition: AnimeSourceDefinition) {
        id = definition.id
        self.definition = definition
        isEnabled = definition.defaultEnabled
        selectedLineID = definition.lines.first?.id
    }

    public var selectedLine: AnimeSourceLine? {
        guard let selectedLineID else {
            return definition.lines.first
        }
        return definition.lines.first { $0.id == selectedLineID } ?? definition.lines.first
    }
}

public struct AnimeSourceCatalogState: Codable, Equatable, Sendable {
    public var instances: [AnimeSourceInstance]
    public var focusedID: String?
    public var displayMode: AnimeSourceDisplayMode

    public init(definitions: [AnimeSourceDefinition]) {
        instances = definitions.map(AnimeSourceInstance.init(definition:))
        focusedID = instances.first?.id
        displayMode = .simple
    }

    public var enabledInstances: [AnimeSourceInstance] {
        instances.filter(\.isEnabled)
    }

    public func instance(id: String) -> AnimeSourceInstance? {
        instances.first { $0.id == id }
    }

    public mutating func focus(sourceID: String?) {
        guard let sourceID, instances.contains(where: { $0.id == sourceID }) else {
            focusedID = instances.first?.id
            return
        }
        focusedID = sourceID
    }

    public mutating func moveFocus(by offset: Int) {
        guard let focusedID,
              let index = instances.firstIndex(where: { $0.id == focusedID })
        else {
            self.focusedID = instances.first?.id
            return
        }

        let nextIndex = min(max(index + offset, 0), instances.count - 1)
        self.focusedID = instances[nextIndex].id
    }

    public mutating func toggleEnabled(sourceID: String) {
        guard let index = instances.firstIndex(where: { $0.id == sourceID }) else {
            return
        }
        instances[index].isEnabled.toggle()
    }

    public mutating func selectLine(sourceID: String, lineID: String) {
        guard let index = instances.firstIndex(where: { $0.id == sourceID }),
              instances[index].definition.lines.contains(where: { $0.id == lineID })
        else {
            return
        }
        instances[index].selectedLineID = lineID
    }

    public mutating func cycleLine(sourceID: String, forward: Bool) {
        guard let index = instances.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let lines = instances[index].definition.lines
        guard lines.isEmpty == false else {
            return
        }

        let currentID = instances[index].selectedLineID ?? lines[0].id
        let currentIndex = lines.firstIndex { $0.id == currentID } ?? 0
        let delta = forward ? 1 : -1
        let nextIndex = (currentIndex + delta + lines.count) % lines.count
        instances[index].selectedLineID = lines[nextIndex].id
    }

    public mutating func moveSource(sourceID: String, offset: Int) {
        guard let index = instances.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let nextIndex = min(max(index + offset, 0), instances.count - 1)
        guard nextIndex != index else {
            return
        }

        let item = instances.remove(at: index)
        instances.insert(item, at: nextIndex)
        focusedID = sourceID
    }

    public func includingDynamicDefinitions(_ definitions: [AnimeSourceDefinition]) -> AnimeSourceCatalogState {
        var next = self
        for definition in definitions where next.instances.contains(where: { $0.id == definition.id }) == false {
            next.instances.append(AnimeSourceInstance(definition: definition))
        }
        if next.focusedID == nil {
            next.focusedID = next.instances.first?.id
        }
        return next
    }

    public func includingDefaultSources() -> AnimeSourceCatalogState {
        includingDynamicDefinitions(AnimeSourceCatalog.defaultSources)
    }

    public func removingUnusableSources() -> AnimeSourceCatalogState {
        var next = self
        next.instances = instances.filter { $0.definition.health == .available }
        if let focusedID, next.instances.contains(where: { $0.id == focusedID }) {
            next.focusedID = focusedID
        } else {
            next.focusedID = next.instances.first?.id
        }
        return next
    }
}

public enum AnimeSourceCatalog {
    public static let defaultSources: [AnimeSourceDefinition] = [
        source("bangumi-youtube", "Bangumi + YouTube", "BY", ["官方 API"]),
        source("mikan", "Mikan Project", "MK", ["RSS / BT"], health: .available, defaultEnabled: false),
        source("dmhy", "動漫花園", "花", ["RSS / BT"], health: .available, defaultEnabled: false),
        source("ani-subs-bt", "ani-subs BT 訂閱", "AS", ["RSS / BT 訂閱"], health: .available, defaultEnabled: false),
        source("ani-subs-css1", "ani-subs CSS1", "CSS", ["Web Selector"], health: .available, defaultEnabled: false),
        source("jellyfin", "Jellyfin", "JF", ["自有媒體庫"], health: .available, defaultEnabled: false),
        source("emby", "Emby", "E", ["自有媒體庫"], health: .available, defaultEnabled: false)
    ]

    private static func source(
        _ id: String,
        _ title: String,
        _ iconLabel: String,
        _ lineTitles: [String],
        health: AnimeSourceHealth = .available,
        defaultEnabled: Bool = true,
        isAdult: Bool = false
    ) -> AnimeSourceDefinition {
        source(
            id,
            title,
            iconLabel,
            lineTitles.enumerated().map { index, title in
                AnimeSourceLine(id: "\(id)-\(index)", title: title)
            },
            health: health,
            defaultEnabled: defaultEnabled,
            isAdult: isAdult
        )
    }

    private static func source(
        _ id: String,
        _ title: String,
        _ iconLabel: String,
        _ lines: [AnimeSourceLine],
        health: AnimeSourceHealth = .available,
        defaultEnabled: Bool = true,
        isAdult: Bool = false
    ) -> AnimeSourceDefinition {
        AnimeSourceDefinition(
            id: id,
            title: title,
            iconLabel: iconLabel,
            lines: lines,
            health: health,
            defaultEnabled: defaultEnabled,
            isAdult: isAdult
        )
    }

}
