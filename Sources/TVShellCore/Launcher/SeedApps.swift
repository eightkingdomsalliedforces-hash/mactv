import Foundation

public enum SeedApps {
    public static let defaultApps: [TVAppProfile] = [
        TVAppProfile(
            name: "YouTube",
            target: .web(URL(string: "https://www.youtube.com/tv")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Apple",
            target: .web(URL(string: "https://www.apple.com")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "瀏覽器",
            target: .web(URL(string: "https://duckduckgo.com")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Safari",
            target: .nativeApp(bundleIdentifier: "com.apple.Safari"),
            controlMode: .hybridNative
        ),
        TVAppProfile(
            name: "影片",
            target: .media(URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "動畫",
            target: .anime,
            controlMode: .web
        ),
        TVAppProfile(
            name: "遙控器",
            target: .web(URL(string: "tv-shell://remote-learning")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "設定",
            target: .web(URL(string: "tv-shell://settings")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "管理",
            target: .web(URL(string: "tv-shell://app-management")!),
            controlMode: .web
        )
    ]
}
