import Foundation

public enum AnimeDemoCatalog {
    public static let sampleVideoURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!

    public static func sourceProvider() -> StaticAnimeSourceProvider {
        let episodes = (1...6).map { number in
            AnimeEpisode(
                id: "demo-episode-\(number)",
                title: "第 \(number) 話",
                number: number,
                identity: AnimeEpisodeIdentity(
                    providerID: "demo",
                    subjectID: "bangumi-demo",
                    episodeID: "\(number)"
                )
            )
        }

        let streams = Dictionary(uniqueKeysWithValues: episodes.map { episode in
            (
                episode.id,
                [
                    AnimeStreamCandidate(url: sampleVideoURL, quality: "1080p", priority: 90),
                    AnimeStreamCandidate(url: sampleVideoURL, quality: "720p", priority: 60)
                ]
            )
        })

        return StaticAnimeSourceProvider(
            id: "demo",
            displayName: "示範動畫源",
            results: [
                AnimeSearchResult(
                    id: "demo-show",
                    title: "示範動畫",
                    subtitle: "Bangumi 彈幕示範",
                    episodes: episodes
                )
            ],
            streams: streams
        )
    }

    public static func danmakuProvider() -> StaticDanmakuProvider {
        StaticDanmakuProvider(comments: [
            DanmakuComment(time: 1.0, text: "彈幕系統啟動"),
            DanmakuComment(time: 4.0, text: "這裡之後會接 Bangumi / Dandanplay"),
            DanmakuComment(time: 8.0, text: "遙控器 Menu 可開關彈幕"),
            DanmakuComment(time: 12.0, text: "下一步接真實動畫源解析"),
            DanmakuComment(time: 18.0, text: "大螢幕模式下字體會保持可讀")
        ])
    }
}
