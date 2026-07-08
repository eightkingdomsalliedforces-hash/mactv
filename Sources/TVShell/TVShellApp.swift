import SwiftUI
import TVShellCore

@main
struct TVShellApp: App {
    @StateObject private var appState = AppState(settingsStore: .applicationSupport())

    var body: some Scene {
        WindowGroup {
            InputRouterView { command in
                appState.handle(command)
            } content: {
                LauncherView()
                    .environmentObject(appState)
                    .background(ShellWindowConfigurator())
            }
                .frame(minWidth: 960, minHeight: 540)
        }
        .commands {
            CommandMenu("MacTV") {
                Button("切換全螢幕") {
                    ShellWindowConfigurator.toggleFocusedWindowFullScreen()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }
    }
}
