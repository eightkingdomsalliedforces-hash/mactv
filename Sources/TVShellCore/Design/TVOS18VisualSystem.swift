import SwiftUI

public enum TVOS18SurfaceRole: Sendable {
    case content
    case row
    case panel
    case alert
}

public struct TVOS18Backdrop: View {
    public let accent: Color?

    public init(accent: Color? = nil) {
        self.accent = accent
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.060, blue: 0.070)
            if let accent {
                accent.opacity(0.22)
            }
            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

public struct TVOS18SurfaceModifier: ViewModifier {
    public let role: TVOS18SurfaceRole
    public let isFocused: Bool
    public let cornerRadius: CGFloat

    public init(role: TVOS18SurfaceRole, isFocused: Bool, cornerRadius: CGFloat) {
        self.role = role
        self.isFocused = isFocused
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .foregroundStyle(foregroundColor)
            .background(fillColor, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(edgeColor, lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowOffset
            )
    }

    private var foregroundColor: Color {
        if role == .row, isFocused {
            return Color.black.opacity(0.94)
        }
        if role == .alert {
            return Color.black.opacity(0.92)
        }
        return Color.white.opacity(0.96)
    }

    private var fillColor: Color {
        switch role {
        case .content:
            return Color.black.opacity(isFocused ? 0.28 : 0.20)
        case .row:
            return isFocused ? Color.white.opacity(0.94) : Color.white.opacity(0.11)
        case .panel:
            return Color(red: 0.10, green: 0.11, blue: 0.12).opacity(0.94)
        case .alert:
            return Color(red: 0.88, green: 0.89, blue: 0.91).opacity(0.98)
        }
    }

    private var edgeColor: Color {
        switch role {
        case .content:
            return Color.white.opacity(isFocused ? 0.16 : 0.08)
        case .row:
            return Color.white.opacity(isFocused ? 0.18 : 0.06)
        case .panel:
            return Color.white.opacity(0.10)
        case .alert:
            return Color.white.opacity(0.30)
        }
    }

    private var shadowOpacity: Double {
        switch role {
        case .content: isFocused ? 0.42 : 0.16
        case .row: isFocused ? 0.30 : 0.08
        case .panel: 0.40
        case .alert: 0.32
        }
    }

    private var shadowRadius: CGFloat {
        switch role {
        case .content: isFocused ? 18 : 6
        case .row: isFocused ? 14 : 3
        case .panel: 26
        case .alert: 24
        }
    }

    private var shadowOffset: CGFloat {
        switch role {
        case .content: isFocused ? 10 : 4
        case .row: isFocused ? 8 : 2
        case .panel, .alert: 14
        }
    }
}

public struct TVOS18ContentFocusModifier: ViewModifier {
    public let isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isFocused: Bool) {
        self.isFocused = isFocused
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused && reduceMotion == false ? 1.06 : 1)
            .offset(y: isFocused && reduceMotion == false ? -10 : 0)
            .brightness(isFocused ? 0.08 : 0)
            .shadow(
                color: .black.opacity(isFocused ? 0.46 : 0.14),
                radius: isFocused ? 20 : 6,
                x: 0,
                y: isFocused ? 12 : 4
            )
            .animation(reduceMotion ? .linear(duration: 0.01) : TVMotion.focus, value: isFocused)
    }
}

public extension View {
    func tvOS18Surface(
        role: TVOS18SurfaceRole,
        isFocused: Bool = false,
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(TVOS18SurfaceModifier(role: role, isFocused: isFocused, cornerRadius: cornerRadius))
    }

    func tvOS18ContentFocus(isFocused: Bool) -> some View {
        modifier(TVOS18ContentFocusModifier(isFocused: isFocused))
    }
}
