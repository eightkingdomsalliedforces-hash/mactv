// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TVShell",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TVShell", targets: ["TVShell"]),
        .executable(name: "TVShellChecks", targets: ["TVShellChecks"])
    ],
    targets: [
        .target(
            name: "TVShellCore",
            path: "Sources/TVShellCore"
        ),
        .executableTarget(
            name: "TVShell",
            dependencies: ["TVShellCore"],
            path: "Sources/TVShell"
        ),
        .executableTarget(
            name: "TVShellChecks",
            dependencies: ["TVShellCore"],
            path: "Sources/TVShellChecks"
        )
    ]
)
