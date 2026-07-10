import Foundation

enum SystemVolumeController {
    static func apply(volume: Double, isMuted: Bool) {
        let level = min(max(Int((volume * 100).rounded()), 0), 100)
        let command = isMuted
            ? "set volume with output muted"
            : "set volume output volume \(level)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", command]
        try? process.run()
    }
}
