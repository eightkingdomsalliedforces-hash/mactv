import SwiftUI

public struct LiquidGlassCardModifier: ViewModifier {
    public let isFocused: Bool
    public let cornerRadius: CGFloat

    public init(isFocused: Bool, cornerRadius: CGFloat = 26) {
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(baseTint)
            )
            .overlay(edgeHighlight)
            .overlay(specularHighlight)
            .shadow(
                color: isFocused ? .cyan.opacity(0.26) : .black.opacity(0.24),
                radius: isFocused ? 42 : 16,
                x: 0,
                y: isFocused ? 26 : 10
            )
            .shadow(
                color: isFocused ? .white.opacity(0.22) : .clear,
                radius: isFocused ? 22 : 0,
                x: 0,
                y: 0
            )
    }

    private var baseTint: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isFocused
                        ? [.white.opacity(0.24), .cyan.opacity(0.16), .purple.opacity(0.2)]
                        : [.white.opacity(0.11), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var edgeHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(isFocused ? 0.92 : 0.32),
                        .white.opacity(isFocused ? 0.24 : 0.08),
                        .cyan.opacity(isFocused ? 0.42 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isFocused ? 4 : 1
            )
    }

    private var specularHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(isFocused ? 0.34 : 0.14), .clear, .white.opacity(isFocused ? 0.10 : 0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
            .padding(isFocused ? 5 : 8)
    }
}

public extension View {
    func liquidGlassCard(isFocused: Bool, cornerRadius: CGFloat = 26) -> some View {
        modifier(LiquidGlassCardModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
