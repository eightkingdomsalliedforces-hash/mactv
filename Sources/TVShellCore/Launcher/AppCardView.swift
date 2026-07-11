import SwiftUI

public struct AppCardView: View {
    public let title: String
    public let symbolName: String
    public let isFocused: Bool
    public let metrics: TVMetrics

    public init(title: String, isFocused: Bool, metrics: TVMetrics = TVMetrics(size: CGSize(width: 1920, height: 1080))) {
        self.title = title
        symbolName = Self.symbolName(for: title)
        self.isFocused = isFocused
        self.metrics = metrics
    }

    public init(app: TVAppProfile, isFocused: Bool, metrics: TVMetrics = TVMetrics(size: CGSize(width: 1920, height: 1080))) {
        title = app.name
        symbolName = Self.symbolName(for: app.name)
        self.isFocused = isFocused
        self.metrics = metrics
    }

    public var body: some View {
        VStack(spacing: 12 * metrics.scale) {
            RoundedRectangle(cornerRadius: 18 * metrics.scale, style: .continuous)
                .fill(iconFill)
                .overlay(
                    Image(systemName: symbolName)
                        .font(.system(size: 58 * metrics.scale, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                )
                .frame(width: metrics.appTileWidth, height: metrics.appTileHeight)
                .tvOS18Surface(role: .content, isFocused: isFocused, cornerRadius: 18 * metrics.scale)
                .tvOS18ContentFocus(isFocused: isFocused)

            Text(title)
                .font(.system(size: 24 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: metrics.appTileWidth)
                .opacity(isFocused ? 1 : 0)
        }
        .animation(TVMotion.focus, value: isFocused)
        .accessibilityLabel(title)
    }

    public static func symbolName(for title: String) -> String {
        switch title.lowercased() {
        case "youtube": "play.rectangle.fill"
        case "bilibili": "play.tv.fill"
        case "動畫": "sparkles.tv.fill"
        case "影片": "film.stack.fill"
        case "瀏覽器", "safari", "apple": "safari.fill"
        case "設定": "gearshape.fill"
        case "遙控器": "dot.radiowaves.left.and.right"
        case "管理": "slider.horizontal.3"
        case "動漫來源": "square.stack.3d.up.fill"
        default: "app.fill"
        }
    }

    private var iconFill: Color {
        switch title.lowercased() {
        case "youtube": Color(red: 0.86, green: 0.08, blue: 0.10)
        case "bilibili": Color(red: 0.94, green: 0.34, blue: 0.52)
        case "動畫": Color(red: 0.40, green: 0.24, blue: 0.72)
        case "影片": Color(red: 0.12, green: 0.46, blue: 0.82)
        case "設定": Color(red: 0.30, green: 0.32, blue: 0.36)
        case "動漫來源": Color(red: 0.08, green: 0.52, blue: 0.50)
        default: Color(red: 0.18, green: 0.20, blue: 0.24)
        }
    }
}
