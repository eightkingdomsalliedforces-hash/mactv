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
        VStack(spacing: 18 * metrics.scale) {
            RoundedRectangle(cornerRadius: 28 * metrics.scale, style: .continuous)
                .fill(iconFill)
                .overlay(
                    Image(systemName: symbolName)
                        .font(.system(size: 76 * metrics.scale, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                )
                .frame(width: metrics.appIconSize, height: metrics.appIconSize)
                .liquidGlassCard(isFocused: isFocused)

            if isFocused {
                Text(title)
                    .font(.system(size: metrics.appTitleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: metrics.appTitleWidth)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Color.clear
                    .frame(height: metrics.appTitleSize * 1.35)
            }
        }
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .rotation3DEffect(.degrees(isFocused ? 1.4 : 0), axis: (x: 1, y: -1, z: 0), perspective: 0.72)
        .offset(y: isFocused ? -16 * metrics.scale : 0)
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

    private var iconFill: LinearGradient {
        LinearGradient(
            colors: isFocused
                ? [.blue.opacity(0.86), .indigo.opacity(0.76), .pink.opacity(0.62)]
                : [.white.opacity(0.22), .blue.opacity(0.28), .indigo.opacity(0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
