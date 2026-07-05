import AppKit
import Foundation

public struct NativeLaunchRequest: Equatable, Sendable {
    public let bundleIdentifier: String

    public init?(profile: TVAppProfile) {
        guard case let .nativeApp(bundleIdentifier) = profile.target else {
            return nil
        }
        self.bundleIdentifier = bundleIdentifier
    }
}

@MainActor
public final class NativeAppRuntime {
    public init() {}

    public func launch(_ profile: TVAppProfile, completion: @escaping @Sendable (Bool, String) -> Void = { _, _ in }) {
        guard let request = NativeLaunchRequest(profile: profile),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.bundleIdentifier)
        else {
            completion(false, "Could not find native app.")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            if let error {
                completion(false, error.localizedDescription)
            } else if app == nil {
                completion(false, "macOS did not return a launched app.")
            } else {
                completion(true, "Opened \(profile.name)")
            }
        }
    }
}
