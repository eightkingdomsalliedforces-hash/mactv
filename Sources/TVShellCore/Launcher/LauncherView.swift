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
            case .appManagement:
                AppManagementView()
            }
        }
    }

    private var launcher: some View {
        GeometryReader { proxy in
            let metrics = TVMetrics(size: proxy.size)

            ZStack(alignment: .topLeading) {
                heroBackground

                VStack(alignment: .leading, spacing: 42 * metrics.scale) {
                    topBar(metrics: metrics)
                        .padding(.top, metrics.topPadding)

                    VStack(alignment: .leading, spacing: 14 * metrics.scale) {
                        Text(focusedApp?.name ?? "TV Shell")
                            .font(.system(size: metrics.heroTitleSize, weight: .bold))
                        Text(heroSubtitle)
                            .font(.system(size: metrics.heroSubtitleSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(.top, 16 * metrics.scale)

                    VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                        ForEach(LauncherLayout.sections(for: appState.apps)) { section in
                            LauncherRowView(section: section, focusedAppID: appState.focusedAppID, metrics: metrics)
                        }
                    }
                    .scaleEffect(appState.displayScale.multiplier(), anchor: .topLeading)

                Spacer()

                if let statusMessage = appState.statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 24 * metrics.scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 24 * metrics.scale)
                        .padding(.vertical, 16 * metrics.scale)
                        .liquidGlassCard(isFocused: true, cornerRadius: 20)
                }

                Text("Use D-pad to move. OK opens. Back or Home returns.")
                        .font(.system(size: metrics.hintSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.bottom, 42 * metrics.scale)
                }
                .padding(.horizontal, metrics.horizontalPadding)
            }
        }
        .foregroundStyle(.white)
    }

    private var focusedApp: TVAppProfile? {
        appState.apps.first { $0.id == appState.focusedAppID }
    }

    private var heroSubtitle: String {
        guard let app = focusedApp else {
            return "Remote-first macOS launcher"
        }

        switch app.target {
        case .media:
            return "Continue watching with cinematic controls"
        case .nativeApp:
            return "Open and control a native macOS app"
        case let .web(url) where url.scheme == "tv-shell":
            return "Configure remotes, scale, and system controls"
        case .web:
            return "Open a big-screen web experience"
        }
    }

    private func topBar(metrics: TVMetrics) -> some View {
        HStack(spacing: 18) {
            Text("TV Shell")
                .font(.system(size: 28 * metrics.scale, weight: .bold))
            Text(appState.displayScale.label)
                .font(.system(size: 24 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(commandLabel)
                .font(.system(size: 23 * metrics.scale, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 28 * metrics.scale)
        .padding(.vertical, 18 * metrics.scale)
        .liquidGlassCard(isFocused: false, cornerRadius: 26)
    }

    private var heroBackground: some View {
        ZStack {
            LinearGradient(
                colors: heroColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [.white.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 780
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.45), value: appState.focusedAppID)
    }

    private var heroColors: [Color] {
        switch appState.wallpaperSource {
        case let .builtIn(preset):
            return preset.palette.colors.map(Color.init(wallpaperColor:))
        case .localFile, .remoteImage:
            return WallpaperPreset.graphite.palette.colors.map(Color.init(wallpaperColor:))
        }
    }

    private var commandLabel: String {
        appState.lastCommand.map { "Last: \($0.description)" } ?? "Waiting for remote"
    }
}

private extension Color {
    init(wallpaperColor: WallpaperColor) {
        self.init(red: wallpaperColor.red, green: wallpaperColor.green, blue: wallpaperColor.blue)
    }
}

private struct LauncherRowView: View {
    let section: LauncherSection
    let focusedAppID: UUID?
    let metrics: TVMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18 * metrics.scale) {
            Text(section.title)
                .font(.system(size: metrics.rowTitleSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: metrics.cardSpacing) {
                ForEach(section.apps) { app in
                    AppCardView(title: app.name, isFocused: app.id == focusedAppID, metrics: metrics)
                }
            }
        }
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
