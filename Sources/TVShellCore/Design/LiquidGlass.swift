import SwiftUI

public struct LiquidGlassCardModifier: ViewModifier {
    public let isFocused: Bool
    public let cornerRadius: CGFloat

    public init(isFocused: Bool, cornerRadius: CGFloat = 26) {
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(
                shape
                    .fill(.regularMaterial)
                    .overlay(baseFill)
                    .overlay(baseTint)
                    .clipShape(shape)
            )
            .clipShape(shape)
            .overlay(edgeHighlight)
            .overlay(specularHighlight)
            .compositingGroup()
            .shadow(
                color: isFocused ? .cyan.opacity(0.18) : .black.opacity(0.18),
                radius: isFocused ? 24 : 8,
                x: 0,
                y: isFocused ? 16 : 6
            )
    }

    private var baseFill: LinearGradient {
        LinearGradient(
            colors: isFocused
                ? [
                    Color(red: 0.42, green: 0.48, blue: 0.58).opacity(0.24),
                    Color(red: 0.12, green: 0.16, blue: 0.24).opacity(0.20)
                ]
                : [
                    Color.white.opacity(0.10),
                    Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.16)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var baseTint: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isFocused
                        ? [.white.opacity(0.22), .cyan.opacity(0.12), .purple.opacity(0.12)]
                        : [.white.opacity(0.10), .white.opacity(0.03)],
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
                lineWidth: isFocused ? 3 : 1
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
