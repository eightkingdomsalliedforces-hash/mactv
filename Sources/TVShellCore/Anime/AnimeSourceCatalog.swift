import Foundation

public enum AnimeSourceHealth: String, Codable, Equatable, Sendable {
    case loading
    case available
    case failed
    case needsCloudflare
    case needsCaptcha
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
}

public enum AnimeSourceCatalog {
    public static let defaultSources: [AnimeSourceDefinition] = [
        source("girigiri", "girigiri 愛動漫", "G", ["在線"]),
        source("omofun111", "omofun111", "O", ["在線"]),
        source("e-acg", "E-ACG", "EA", ["E-ACG"]),
        source("hoibi", "吼哔動漫", "吼", [
            AnimeSourceLine(id: "hoibi-2", title: "吼哔2線"),
            AnimeSourceLine(id: "hoibi-1", title: "吼哔1線"),
            AnimeSourceLine(id: "hoibi-4", title: "吼哔4線")
        ]),
        source("fengche", "風車影視", "風", ["動漫大全", "線路②", "線路①", "線路③", "備用②", "備用③"]),
        source("qukanba", "去看吧", "去", ["EDD"]),
        source("haixing", "海星動漫", "海", ["播放I", "播放II", "播放III", "播放IV", "播放V", "播放VI"]),
        source("fanqie", "番茄動漫", "番", ["番茄2線", "番茄1線", "速播資源1"]),
        source("hanime1-720p", "hanime1[720p]", "720", ["720p"], defaultEnabled: false, isAdult: true),
        source("uzvod", "UZVOD", "UZ", ["在線"]),
        source("ark", "次元方舟", "舟", ["在線"]),
        source("2k", "2k動漫", "2K", ["極速資源-LZ", "極速資源-FF"]),
        source("blue-ray", "高清藍光", "藍", ["高清藍光-OF", "高清藍光-LM", "高清藍光-LX"]),
        source("dilidili", "嘀哩嘀哩", "嘀", ["在線"]),
        source("fantuan", "飯團動漫", "飯", ["線路二", "線路四", "線路六", "線路三"]),
        source("mx", "MX動漫", "MX", ["在線"], health: .loading),
        source("miaowu", "喵物次元", "喵", ["Cloudflare 驗證"], health: .needsCloudflare, defaultEnabled: false),
        source("new-youku", "新優酷", "NU", ["驗證碼"], health: .needsCaptcha, defaultEnabled: false),
        source("dongmandan", "動漫蛋", "蛋", ["在線"], health: .loading),
        source("mengdao", "萌道動漫", "萌", ["播放地址"]),
        source("gugufan", "咕咕番", "咕", [
            AnimeSourceLine(id: "gugufan-a", title: "咕咕A線"),
            AnimeSourceLine(id: "gugufan-b", title: "咕咕B線(已弃用)", isDeprecated: true)
        ]),
        source("first-anime", "第一動漫", "一", ["重試"], health: .failed, defaultEnabled: false),
        source("sakura", "櫻花動漫", "櫻", ["重試"], health: .failed, defaultEnabled: false)
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
