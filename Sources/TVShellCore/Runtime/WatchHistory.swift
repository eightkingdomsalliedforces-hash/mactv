import Foundation

public enum WatchHistoryKind: String, Codable, Equatable, Sendable {
    case anime
    case youtube
    case media
    case web
}

public struct WatchHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var subtitle: String?
    public var kind: WatchHistoryKind
    public var mediaID: String?
    public var resumeTimeSeconds: Double
    public var durationSeconds: Double?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        kind: WatchHistoryKind,
        mediaID: String? = nil,
        resumeTimeSeconds: Double = 0,
        durationSeconds: Double? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.mediaID = mediaID
        self.resumeTimeSeconds = max(0, resumeTimeSeconds)
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
    }

    public var resumeTimeLabel: String {
        Self.timeLabel(for: resumeTimeSeconds)
    }

    public var progressSubtitle: String {
        let base = subtitle ?? kind.rawValue
        guard resumeTimeSeconds >= 1 else {
            return base
        }
        return "\(base) · \(resumeTimeLabel)"
    }

    public static func timeLabel(for seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let seconds = rounded % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
