import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            Text("Settings")
                .font(.system(size: 76, weight: .bold))

            VStack(alignment: .leading, spacing: 24) {
                Text("UI Scale")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 28) {
                    Text("<")
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))

                    Text(appState.displayScale.label)
                        .font(.system(size: 66, weight: .bold))
                        .frame(width: 260)
                        .padding(.vertical, 26)
                        .liquidGlassCard(isFocused: true, cornerRadius: 24)

                    Text(">")
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Text("Use Left/Right or OK to change scale. Home or Back returns to the launcher.")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.64))
            }

            PermissionStatusView()

            Spacer()
        }
        .foregroundStyle(.white)
        .padding(96)
    }
}
