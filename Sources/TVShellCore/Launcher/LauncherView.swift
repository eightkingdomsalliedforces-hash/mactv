import SwiftUI

public struct LauncherView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.12, blue: 0.18),
                    Color(red: 0.15, green: 0.10, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch appState.activeRuntime {
            case .launcher:
                launcher
            case let .web(app):
                WebAppRuntimeView(app: app)
            case let .media(app):
                MediaRuntimeView(app: app)
            case let .native(app):
                NativeRuntimeInterimView(app: app)
            case .remoteLearning:
                RemoteLearningView()
            case .settings:
                SettingsView()
            }
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 72) {
            HStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("TV Shell")
                        .font(.system(size: 76, weight: .bold))
                    Text("Remote-first macOS launcher")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Text(commandLabel)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .background(.white.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 54) {
                ForEach(appState.apps) { app in
                    AppCardView(title: app.name, isFocused: app.id == appState.focusedAppID)
                }
            }
            .scaleEffect(appState.displayScale.multiplier(), anchor: .leading)

            Spacer()

            PermissionStatusView()

            Text("Use arrows or remote D-pad. OK opens. Home returns here.")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 96)
        .padding(.top, 80)
        .padding(.bottom, 64)
    }

    private var commandLabel: String {
        guard let command = appState.lastCommand else {
            return "Waiting for remote"
        }
        return "Last: \(command.description)"
    }
}

private struct NativeRuntimeInterimView: View {
    let app: TVAppProfile

    var body: some View {
        VStack(spacing: 32) {
            Text(app.name)
                .font(.system(size: 72, weight: .bold))
            Text("Native app launched. Press Home to return.")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Hybrid Accessibility control foundation is enabled in this phase.")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .foregroundStyle(.white)
    }
}
