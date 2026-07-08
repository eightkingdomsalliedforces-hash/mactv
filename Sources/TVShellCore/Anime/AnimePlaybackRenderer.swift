import Foundation

public enum AnimePlaybackRenderer: Equatable, Sendable {
    case avPlayer
    case vlc

    public static func renderer(for url: URL) -> AnimePlaybackRenderer {
        let pathExtension = url.pathExtension.lowercased()
        if vlcExtensions.contains(pathExtension) {
            return .vlc
        }
        return .avPlayer
    }

    public static func canUseAVPlayer(for url: URL) -> Bool {
        renderer(for: url) == .avPlayer
    }

    private static let vlcExtensions: Set<String> = [
        "mkv", "avi", "webm", "flv", "wmv", "m2ts", "ts"
    ]
}
