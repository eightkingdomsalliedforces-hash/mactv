import SwiftUI

public struct AppCardView: View {
    public let title: String
    public let isFocused: Bool

    public init(title: String, isFocused: Bool) {
        self.title = title
        self.isFocused = isFocused
    }

    public var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(iconFill)
                .overlay(
                    Text(String(title.prefix(1)))
                        .font(.system(size: 82, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .frame(width: 220, height: 220)
                .liquidGlassCard(isFocused: isFocused)

            Text(title)
                .font(.system(size: 34, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 260)
        }
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isFocused)
        .accessibilityLabel(title)
    }

    private var iconFill: LinearGradient {
        LinearGradient(
            colors: isFocused
                ? [.blue.opacity(0.75), .purple.opacity(0.62), .pink.opacity(0.52)]
                : [.white.opacity(0.15), .blue.opacity(0.18), .purple.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
