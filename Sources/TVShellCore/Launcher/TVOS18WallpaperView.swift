import AppKit
import SwiftUI

public struct TVOS18WallpaperView: View {
    public let source: WallpaperSource

    public init(source: WallpaperSource) {
        self.source = source
    }

    public var body: some View {
        ZStack {
            wallpaper
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .black.opacity(0.12), location: 0.50),
                    .init(color: .black.opacity(0.64), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var wallpaper: some View {
        switch source {
        case let .builtIn(preset):
            presetGradient(preset)
        case let .localFile(url):
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackGradient
            }
        case let .remoteImage(url):
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    fallbackGradient
                @unknown default:
                    fallbackGradient
                }
            }
        }
    }

    private func presetGradient(_ preset: WallpaperPreset) -> some View {
        let colors = preset.palette.colors.map {
            Color(red: $0.red, green: $0.green, blue: $0.blue)
        }
        return LinearGradient(
            colors: colors.isEmpty ? [.black, Color(white: 0.14)] : colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.08, blue: 0.10), Color(red: 0.18, green: 0.20, blue: 0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
