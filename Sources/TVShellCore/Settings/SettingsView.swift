import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            Text("Settings")
                .font(.system(size: 76, weight: .bold))

            SettingsOptionRow(
                title: "UI Scale",
                value: appState.displayScale.label,
                isFocused: appState.settingsFocus == .scale
            )

            SettingsOptionRow(
                title: "Wallpaper",
                value: wallpaperLabel,
                isFocused: appState.settingsFocus == .wallpaper
            )

            Text("Use Up/Down to choose a setting. Left/Right or OK changes it. Home or Back returns to the launcher.")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))

            PermissionStatusView()

            Spacer()
        }
        .foregroundStyle(.white)
        .padding(96)
    }

    private var wallpaperLabel: String {
        switch appState.wallpaperSource {
        case let .builtIn(preset):
            preset.title
        case .localFile:
            "Local Image"
        case .remoteImage:
            "Provider Image"
        }
    }
}

private struct SettingsOptionRow: View {
    let title: String
    let value: String
    let isFocused: Bool

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.system(size: 58, weight: .bold))
            }

            Spacer()

            Text("<  >")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
        .liquidGlassCard(isFocused: isFocused, cornerRadius: 26)
    }
}
