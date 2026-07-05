import SwiftUI

public struct PermissionStatusView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Remote Control Permissions")
                .font(.system(size: 44, weight: .bold))

            HStack(spacing: 18) {
                Circle()
                    .fill(AccessibilityScanner.isTrusted ? .green : .orange)
                    .frame(width: 22, height: 22)

                Text(AccessibilityScanner.isTrusted ? "Accessibility enabled" : "Accessibility needed for deep native app control")
                    .font(.system(size: 28, weight: .medium))
            }

            Text("Open Remote setup and press OK to request permission.")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
        .padding(30)
        .liquidGlassCard(isFocused: AccessibilityScanner.isTrusted == false, cornerRadius: 18)
    }
}
