import SwiftUI

public struct TVControlBackdrop: View {
    private let accent: Color?

    public init(accent: Color? = nil) {
        self.accent = accent
    }

    public var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.055, blue: 0.075)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.08)
            if let accent {
                accent.opacity(0.28)
            }
            Color.black.opacity(0.10)
        }
        .ignoresSafeArea()
    }
}

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
                    .fill(.ultraThinMaterial)
                    .overlay(Color.white.opacity(isFocused ? 0.13 : 0.07))
                    .overlay(Color.black.opacity(isFocused ? 0.06 : 0.12))
                    .clipShape(shape)
            )
            .clipShape(shape)
            .overlay(edgeHighlight)
            .compositingGroup()
            .shadow(
                color: .black.opacity(isFocused ? 0.38 : 0.20),
                radius: isFocused ? 22 : 8,
                x: 0,
                y: isFocused ? 14 : 6
            )
    }

    private var edgeHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                .white.opacity(isFocused ? 0.94 : 0.16),
                lineWidth: isFocused ? 3 : 1
            )
    }
}

public extension View {
    func liquidGlassCard(isFocused: Bool, cornerRadius: CGFloat = 26) -> some View {
        modifier(LiquidGlassCardModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
