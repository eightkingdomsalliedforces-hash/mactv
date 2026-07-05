import Foundation

public struct LauncherSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let apps: [TVAppProfile]

    public init(id: String, title: String, apps: [TVAppProfile]) {
        self.id = id
        self.title = title
        self.apps = apps
    }
}

public enum LauncherLayout {
    public static func sections(for apps: [TVAppProfile]) -> [LauncherSection] {
        let media = apps.filter { app in
            if case .media = app.target { return true }
            return false
        }
        let webAndNative = apps.filter { app in
            switch app.target {
            case let .web(url):
                return url.scheme != "tv-shell"
            case .nativeApp:
                return true
            case .media:
                return false
            }
        }
        let tools = apps.filter { app in
            if case let .web(url) = app.target {
                return url.scheme == "tv-shell"
            }
            return false
        }

        return [
            LauncherSection(id: "continue", title: "Continue Watching", apps: media),
            LauncherSection(id: "apps", title: "Apps", apps: webAndNative),
            LauncherSection(id: "tools", title: "Controls", apps: tools)
        ].filter { $0.apps.isEmpty == false }
    }

    public static func focusedApp(
        after command: RemoteCommand,
        currentID: UUID?,
        sections: [LauncherSection]
    ) -> UUID? {
        let flattened = sections.flatMap(\.apps)
        guard let currentID,
              let position = position(of: currentID, in: sections)
        else {
            return flattened.first?.id
        }

        switch command {
        case .left:
            let nextColumn = max(position.column - 1, 0)
            return sections[position.row].apps[nextColumn].id
        case .right:
            let nextColumn = min(position.column + 1, sections[position.row].apps.count - 1)
            return sections[position.row].apps[nextColumn].id
        case .up:
            let nextRow = max(position.row - 1, 0)
            let nextColumn = min(position.column, sections[nextRow].apps.count - 1)
            return sections[nextRow].apps[nextColumn].id
        case .down:
            let nextRow = min(position.row + 1, sections.count - 1)
            let nextColumn = min(position.column, sections[nextRow].apps.count - 1)
            return sections[nextRow].apps[nextColumn].id
        default:
            return currentID
        }
    }

    private static func position(of id: UUID, in sections: [LauncherSection]) -> (row: Int, column: Int)? {
        for row in sections.indices {
            if let column = sections[row].apps.firstIndex(where: { $0.id == id }) {
                return (row, column)
            }
        }
        return nil
    }
}
