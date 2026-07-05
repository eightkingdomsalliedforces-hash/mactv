# Remote-First TV Shell Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first runnable macOS TV shell milestone where remote input, focus movement, Home/Back behavior, web control, native app launching, and Accessibility-assisted control are working before visual polish.

**Architecture:** Create a Swift Package Manager macOS app that runs with `swift run TVShell`, using pure Swift modules for tested remote and focus logic, plus AppKit/SwiftUI views for the shell. Route every physical input through `RemoteCommand`, then dispatch it to the active runtime: launcher, web, native keyboard, or native accessibility.

**Tech Stack:** Swift 6-compatible SPM, SwiftUI, AppKit, WebKit, ApplicationServices Accessibility APIs, XCTest.

---

## Scope Boundary

This plan implements Phase 1 from `docs/superpowers/specs/2026-07-05-remote-first-tv-shell-design.md`.

Included:

- Runnable macOS shell.
- Keyboard-backed remote input.
- Remote command normalization.
- Remote learning data model and store.
- Directional FocusEngine.
- Large-screen launcher with visible focus.
- Web app runtime using `WKWebView`.
- Native app launching using `NSWorkspace`.
- Accessibility permission check and initial AX element scanning.
- Reliable Home path back to the launcher from internal runtimes.

Deferred to later phases:

- CoreHID per-device remote discovery.
- Full media runtime with AVPlayer.
- Advanced animation polish.
- App icon extraction quality pass.
- Sandboxed distribution strategy.
- Installer, notarization, and `.app` bundle packaging.

## File Structure

Create this structure under `/Users/kris/Documents/Codex/2026-07-05/apple-tv-tvos-macos-1-apple`:

```text
Package.swift
Sources/
  TVShell/
    TVShellApp.swift
    App/
      AppState.swift
      ShellWindowManager.swift
    Input/
      RemoteCommand.swift
      RawInputEvent.swift
      KeyCodeMapper.swift
      RemoteMappingStore.swift
      InputRouter.swift
    Focus/
      FocusEngine.swift
      FocusNode.swift
      FocusTypes.swift
    Launcher/
      LauncherView.swift
      AppCardView.swift
      SeedApps.swift
    Runtime/
      AppRuntime.swift
      WebAppRuntimeView.swift
      NativeAppRuntime.swift
      AccessibilityScanner.swift
    Settings/
      RemoteLearningView.swift
      PermissionStatusView.swift
Tests/
  TVShellTests/
    KeyCodeMapperTests.swift
    RemoteMappingStoreTests.swift
    FocusEngineTests.swift
    NativeAppRuntimeTests.swift
```

The testable files must avoid depending on SwiftUI views. `RemoteCommand`, `KeyCodeMapper`, `RemoteMappingStore`, `FocusEngine`, and `NativeAppRuntime` should be usable from XCTest.

---

### Task 1: Create Swift Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/TVShell/TVShellApp.swift`
- Create: `Tests/TVShellTests/PackageSmokeTests.swift`

- [ ] **Step 1: Initialize git repository**

Run:

```bash
git init
```

Expected: repository initialized in the workspace.

- [ ] **Step 2: Create package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TVShell",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TVShell", targets: ["TVShell"])
    ],
    targets: [
        .executableTarget(
            name: "TVShell",
            path: "Sources/TVShell"
        ),
        .testTarget(
            name: "TVShellTests",
            dependencies: ["TVShell"],
            path: "Tests/TVShellTests"
        )
    ]
)
```

- [ ] **Step 3: Create minimal runnable app**

Create `Sources/TVShell/TVShellApp.swift`:

```swift
import SwiftUI

@main
struct TVShellApp: App {
    var body: some Scene {
        WindowGroup {
            Text("TV Shell")
                .font(.system(size: 64, weight: .bold))
                .frame(minWidth: 1280, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 4: Create smoke test**

Create `Tests/TVShellTests/PackageSmokeTests.swift`:

```swift
import XCTest
@testable import TVShell

final class PackageSmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test
```

Expected: `PackageSmokeTests.testPackageLoads` passes.

- [ ] **Step 6: Run the app**

Run:

```bash
swift run TVShell
```

Expected: a macOS window opens and shows "TV Shell" in large text.

- [ ] **Step 7: Commit**

Run:

```bash
git add Package.swift Sources Tests
git commit -m "chore: create remote-first tv shell package"
```

Expected: one commit is created.

---

### Task 2: Add Remote Command Normalization

**Files:**
- Create: `Sources/TVShell/Input/RemoteCommand.swift`
- Create: `Sources/TVShell/Input/RawInputEvent.swift`
- Create: `Sources/TVShell/Input/KeyCodeMapper.swift`
- Create: `Tests/TVShellTests/KeyCodeMapperTests.swift`

- [ ] **Step 1: Write failing mapper tests**

Create `Tests/TVShellTests/KeyCodeMapperTests.swift`:

```swift
import XCTest
@testable import TVShell

final class KeyCodeMapperTests: XCTestCase {
    func testArrowKeysMapToDirectionalCommands() {
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 126, characters: nil, modifiers: [])), .up)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 125, characters: nil, modifiers: [])), .down)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 123, characters: nil, modifiers: [])), .left)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 124, characters: nil, modifiers: [])), .right)
    }

    func testSelectBackHomeAndPlaybackMappings() {
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 36, characters: "\r", modifiers: [])), .select)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 53, characters: "\u{1b}", modifiers: [])), .back)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 4, characters: "h", modifiers: [.command])), .home)
        XCTAssertEqual(KeyCodeMapper.default.command(for: .keyboard(keyCode: 49, characters: " ", modifiers: [])), .playPause)
    }

    func testUnknownInputReturnsNil() {
        XCTAssertNil(KeyCodeMapper.default.command(for: .keyboard(keyCode: 8, characters: "c", modifiers: [])))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter KeyCodeMapperTests
```

Expected: compile fails because `KeyCodeMapper`, `RawInputEvent`, and `RemoteCommand` do not exist.

- [ ] **Step 3: Implement RemoteCommand**

Create `Sources/TVShell/Input/RemoteCommand.swift`:

```swift
public indirect enum RemoteCommand: Equatable, Codable, Sendable {
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case menu
    case playPause
    case rewind
    case fastForward
    case volumeUp
    case volumeDown
    case mute
    case longPress(RemoteCommand)
}
```

- [ ] **Step 4: Implement RawInputEvent**

Create `Sources/TVShell/Input/RawInputEvent.swift`:

```swift
public enum RemoteModifier: String, Codable, Equatable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public enum RawInputEvent: Equatable, Hashable, Codable, Sendable {
    case keyboard(keyCode: UInt16, characters: String?, modifiers: Set<RemoteModifier>)
    case media(systemCode: Int)
    case hid(usagePage: Int, usage: Int)
}
```

- [ ] **Step 5: Implement KeyCodeMapper**

Create `Sources/TVShell/Input/KeyCodeMapper.swift`:

```swift
public struct KeyCodeMapper: Equatable, Sendable {
    public static let `default` = KeyCodeMapper()

    public init() {}

    public func command(for event: RawInputEvent) -> RemoteCommand? {
        switch event {
        case let .keyboard(keyCode, characters, modifiers):
            return commandForKeyboard(keyCode: keyCode, characters: characters, modifiers: modifiers)
        case let .media(systemCode):
            return commandForMedia(systemCode: systemCode)
        case let .hid(usagePage, usage):
            return commandForHID(usagePage: usagePage, usage: usage)
        }
    }

    private func commandForKeyboard(keyCode: UInt16, characters: String?, modifiers: Set<RemoteModifier>) -> RemoteCommand? {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        case 36, 76: return .select
        case 53: return .back
        case 49: return .playPause
        case 4 where modifiers.contains(.command): return .home
        case 46 where modifiers.contains(.command): return .menu
        default:
            if characters == "\r" { return .select }
            if characters == "\u{1b}" { return .back }
            return nil
        }
    }

    private func commandForMedia(systemCode: Int) -> RemoteCommand? {
        switch systemCode {
        case 16: return .playPause
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        default: return nil
        }
    }

    private func commandForHID(usagePage: Int, usage: Int) -> RemoteCommand? {
        if usagePage == 0x0C {
            switch usage {
            case 0xCD: return .playPause
            case 0xE9: return .volumeUp
            case 0xEA: return .volumeDown
            case 0xE2: return .mute
            default: return nil
            }
        }
        return nil
    }
}
```

- [ ] **Step 6: Run mapper tests**

Run:

```bash
swift test --filter KeyCodeMapperTests
```

Expected: all `KeyCodeMapperTests` pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/TVShell/Input Tests/TVShellTests/KeyCodeMapperTests.swift
git commit -m "feat: normalize remote input commands"
```

Expected: one commit is created.

---

### Task 3: Add Remote Learning Store

**Files:**
- Create: `Sources/TVShell/Input/RemoteMappingStore.swift`
- Create: `Tests/TVShellTests/RemoteMappingStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/TVShellTests/RemoteMappingStoreTests.swift`:

```swift
import XCTest
@testable import TVShell

final class RemoteMappingStoreTests: XCTestCase {
    func testLearnedMappingOverridesDefaultUnknownInput() throws {
        var store = RemoteMappingStore()
        let raw = RawInputEvent.keyboard(keyCode: 8, characters: "c", modifiers: [])

        XCTAssertNil(store.command(for: raw))

        store.learn(raw, as: .home)

        XCTAssertEqual(store.command(for: raw), .home)
    }

    func testMappingsRoundTripThroughJSON() throws {
        var store = RemoteMappingStore()
        let raw = RawInputEvent.hid(usagePage: 12, usage: 999)
        store.learn(raw, as: .back)

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(RemoteMappingStore.self, from: data)

        XCTAssertEqual(decoded.command(for: raw), .back)
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter RemoteMappingStoreTests
```

Expected: compile fails because `RemoteMappingStore` does not exist.

- [ ] **Step 3: Implement RemoteMappingStore**

Create `Sources/TVShell/Input/RemoteMappingStore.swift`:

```swift
public struct RemoteMappingStore: Codable, Equatable, Sendable {
    private var learnedMappings: [RawInputEvent: RemoteCommand]
    private var fallbackMapper: KeyCodeMapper

    public init(
        learnedMappings: [RawInputEvent: RemoteCommand] = [:],
        fallbackMapper: KeyCodeMapper = .default
    ) {
        self.learnedMappings = learnedMappings
        self.fallbackMapper = fallbackMapper
    }

    enum CodingKeys: String, CodingKey {
        case learnedMappings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        learnedMappings = try container.decode([RawInputEvent: RemoteCommand].self, forKey: .learnedMappings)
        fallbackMapper = .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(learnedMappings, forKey: .learnedMappings)
    }

    public mutating func learn(_ event: RawInputEvent, as command: RemoteCommand) {
        learnedMappings[event] = command
    }

    public func command(for event: RawInputEvent) -> RemoteCommand? {
        learnedMappings[event] ?? fallbackMapper.command(for: event)
    }
}
```

- [ ] **Step 4: Run store tests**

Run:

```bash
swift test --filter RemoteMappingStoreTests
```

Expected: all `RemoteMappingStoreTests` pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/TVShell/Input/RemoteMappingStore.swift Tests/TVShellTests/RemoteMappingStoreTests.swift
git commit -m "feat: add remote learning mapping store"
```

Expected: one commit is created.

---

### Task 4: Add Directional FocusEngine

**Files:**
- Create: `Sources/TVShell/Focus/FocusTypes.swift`
- Create: `Sources/TVShell/Focus/FocusNode.swift`
- Create: `Sources/TVShell/Focus/FocusEngine.swift`
- Create: `Tests/TVShellTests/FocusEngineTests.swift`

- [ ] **Step 1: Write failing focus tests**

Create `Tests/TVShellTests/FocusEngineTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import TVShell

final class FocusEngineTests: XCTestCase {
    func testMovesRightToNearestCandidateInSameRow() {
        var engine = FocusEngine()
        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 140, y: 180, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")

        XCTAssertEqual(engine.move(.right), "b")
    }

    func testMovesDownToNearestVerticalCandidate() {
        var engine = FocusEngine()
        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 20, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "c", rect: CGRect(x: 280, y: 160, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true)
        ])
        engine.setFocus("a")

        XCTAssertEqual(engine.move(.down), "b")
    }

    func testRecoverFocusChoosesFirstVisibleNode() {
        var engine = FocusEngine()
        engine.register([
            FocusNode(id: "a", rect: CGRect(x: 0, y: 0, width: 100, height: 100), group: "home", priority: 0, acceptsSelect: true),
            FocusNode(id: "b", rect: CGRect(x: 140, y: 0, width: 100, height: 100), group: "home", priority: 1, acceptsSelect: true)
        ])

        XCTAssertEqual(engine.recoverFocus(in: "home"), "b")
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter FocusEngineTests
```

Expected: compile fails because focus types do not exist.

- [ ] **Step 3: Implement focus types**

Create `Sources/TVShell/Focus/FocusTypes.swift`:

```swift
public typealias FocusID = String
public typealias FocusGroupID = String

public enum FocusDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}
```

- [ ] **Step 4: Implement FocusNode**

Create `Sources/TVShell/Focus/FocusNode.swift`:

```swift
import CoreGraphics

public struct FocusNode: Equatable, Sendable {
    public let id: FocusID
    public let rect: CGRect
    public let group: FocusGroupID
    public let priority: Int
    public let acceptsSelect: Bool
    public let acceptsLongPress: Bool

    public init(
        id: FocusID,
        rect: CGRect,
        group: FocusGroupID,
        priority: Int,
        acceptsSelect: Bool,
        acceptsLongPress: Bool = false
    ) {
        self.id = id
        self.rect = rect
        self.group = group
        self.priority = priority
        self.acceptsSelect = acceptsSelect
        self.acceptsLongPress = acceptsLongPress
    }
}
```

- [ ] **Step 5: Implement FocusEngine**

Create `Sources/TVShell/Focus/FocusEngine.swift`:

```swift
import CoreGraphics

public struct FocusEngine: Sendable {
    private var nodesByID: [FocusID: FocusNode] = [:]
    private var currentID: FocusID?

    public init() {}

    public var currentFocus: FocusID? {
        currentID
    }

    public mutating func register(_ nodes: [FocusNode]) {
        nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        if let currentID, nodesByID[currentID] == nil {
            self.currentID = nil
        }
    }

    public mutating func setFocus(_ id: FocusID?) {
        guard let id else {
            currentID = nil
            return
        }
        if nodesByID[id] != nil {
            currentID = id
        }
    }

    @discardableResult
    public mutating func move(_ direction: FocusDirection) -> FocusID? {
        guard let currentID, let current = nodesByID[currentID] else {
            return recoverFocus(in: nil)
        }

        let candidates = nodesByID.values.filter { node in
            node.id != current.id && node.group == current.group && isCandidate(node.rect, from: current.rect, direction: direction)
        }

        guard let next = candidates.min(by: { score($0.rect, from: current.rect, direction: direction) < score($1.rect, from: current.rect, direction: direction) }) else {
            return currentID
        }

        self.currentID = next.id
        return next.id
    }

    @discardableResult
    public mutating func recoverFocus(in group: FocusGroupID?) -> FocusID? {
        let candidates = nodesByID.values.filter { group == nil || $0.group == group }
        guard let recovered = candidates.sorted(by: {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
            return $0.rect.minX < $1.rect.minX
        }).first else {
            currentID = nil
            return nil
        }
        currentID = recovered.id
        return recovered.id
    }

    private func isCandidate(_ candidate: CGRect, from current: CGRect, direction: FocusDirection) -> Bool {
        switch direction {
        case .up: return candidate.midY < current.midY
        case .down: return candidate.midY > current.midY
        case .left: return candidate.midX < current.midX
        case .right: return candidate.midX > current.midX
        }
    }

    private func score(_ candidate: CGRect, from current: CGRect, direction: FocusDirection) -> CGFloat {
        let primary: CGFloat
        let secondary: CGFloat

        switch direction {
        case .up:
            primary = current.midY - candidate.midY
            secondary = abs(current.midX - candidate.midX)
        case .down:
            primary = candidate.midY - current.midY
            secondary = abs(current.midX - candidate.midX)
        case .left:
            primary = current.midX - candidate.midX
            secondary = abs(current.midY - candidate.midY)
        case .right:
            primary = candidate.midX - current.midX
            secondary = abs(current.midY - candidate.midY)
        }

        return primary * 10_000 + secondary
    }
}
```

- [ ] **Step 6: Run focus tests**

Run:

```bash
swift test --filter FocusEngineTests
```

Expected: all `FocusEngineTests` pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/TVShell/Focus Tests/TVShellTests/FocusEngineTests.swift
git commit -m "feat: add directional focus engine"
```

Expected: one commit is created.

---

### Task 5: Add App State and Runtime Routing

**Files:**
- Create: `Sources/TVShell/App/AppState.swift`
- Create: `Sources/TVShell/Runtime/AppRuntime.swift`
- Create: `Sources/TVShell/Launcher/SeedApps.swift`

- [ ] **Step 1: Create runtime model**

Create `Sources/TVShell/Runtime/AppRuntime.swift`:

```swift
import Foundation

public enum RuntimeKind: String, Codable, Equatable, Sendable {
    case launcher
    case web
    case native
}

public enum LaunchTarget: Equatable, Codable, Sendable {
    case web(URL)
    case nativeApp(bundleIdentifier: String)
}

public struct TVAppProfile: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var target: LaunchTarget
    public var controlMode: ControlMode

    public init(id: UUID = UUID(), name: String, target: LaunchTarget, controlMode: ControlMode) {
        self.id = id
        self.name = name
        self.target = target
        self.controlMode = controlMode
    }
}

public enum ControlMode: String, Codable, Equatable, Sendable {
    case web
    case nativeKeyboard
    case nativeAccessibility
    case hybridNative
}

public enum ActiveRuntime: Equatable, Sendable {
    case launcher
    case web(TVAppProfile)
    case native(TVAppProfile)
}
```

- [ ] **Step 2: Create AppState**

Create `Sources/TVShell/App/AppState.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var activeRuntime: ActiveRuntime = .launcher
    @Published public var focusedAppID: UUID?
    @Published public var lastCommand: RemoteCommand?
    @Published public var apps: [TVAppProfile]

    public init(apps: [TVAppProfile] = SeedApps.defaultApps) {
        self.apps = apps
        self.focusedAppID = apps.first?.id
    }

    public func handle(_ command: RemoteCommand) {
        lastCommand = command

        switch activeRuntime {
        case .launcher:
            handleLauncher(command)
        case .web:
            handleRuntimeCommand(command)
        case .native:
            handleRuntimeCommand(command)
        }
    }

    private func handleLauncher(_ command: RemoteCommand) {
        switch command {
        case .left:
            moveFocusedApp(by: -1)
        case .right:
            moveFocusedApp(by: 1)
        case .select:
            openFocusedApp()
        case .home:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home {
            activeRuntime = .launcher
        }
    }

    private func moveFocusedApp(by offset: Int) {
        guard let focusedAppID, let index = apps.firstIndex(where: { $0.id == focusedAppID }) else {
            self.focusedAppID = apps.first?.id
            return
        }
        let nextIndex = min(max(index + offset, 0), apps.count - 1)
        self.focusedAppID = apps[nextIndex].id
    }

    private func openFocusedApp() {
        guard let app = apps.first(where: { $0.id == focusedAppID }) else {
            return
        }
        switch app.target {
        case .web:
            activeRuntime = .web(app)
        case .nativeApp:
            activeRuntime = .native(app)
        }
    }
}
```

- [ ] **Step 3: Create seed apps**

Create `Sources/TVShell/Launcher/SeedApps.swift`:

```swift
import Foundation

public enum SeedApps {
    public static let defaultApps: [TVAppProfile] = [
        TVAppProfile(
            name: "YouTube",
            target: .web(URL(string: "https://www.youtube.com/tv")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Apple",
            target: .web(URL(string: "https://www.apple.com")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Safari",
            target: .nativeApp(bundleIdentifier: "com.apple.Safari"),
            controlMode: .hybridNative
        )
    ]
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/TVShell/App Sources/TVShell/Runtime/AppRuntime.swift Sources/TVShell/Launcher/SeedApps.swift
git commit -m "feat: add runtime routing state"
```

Expected: one commit is created.

---

### Task 6: Add Keyboard Input Router to the Shell

**Files:**
- Create: `Sources/TVShell/Input/InputRouter.swift`
- Modify: `Sources/TVShell/TVShellApp.swift`

- [ ] **Step 1: Implement InputRouter view wrapper**

Create `Sources/TVShell/Input/InputRouter.swift`:

```swift
import AppKit
import SwiftUI

public struct InputRouterView<Content: View>: NSViewRepresentable {
    private let content: Content
    private let onCommand: (RemoteCommand) -> Void

    public init(onCommand: @escaping (RemoteCommand) -> Void, @ViewBuilder content: () -> Content) {
        self.onCommand = onCommand
        self.content = content()
    }

    public func makeNSView(context: Context) -> HostingKeyView<Content> {
        let view = HostingKeyView(rootView: content)
        view.onCommand = onCommand
        return view
    }

    public func updateNSView(_ nsView: HostingKeyView<Content>, context: Context) {
        nsView.rootView = content
        nsView.onCommand = onCommand
    }
}

public final class HostingKeyView<Content: View>: NSHostingView<Content> {
    public var onCommand: ((RemoteCommand) -> Void)?
    private let mapper = KeyCodeMapper.default

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    public override func keyDown(with event: NSEvent) {
        let raw = RawInputEvent.keyboard(
            keyCode: event.keyCode,
            characters: event.characters,
            modifiers: RemoteModifier.from(event.modifierFlags)
        )

        if let command = mapper.command(for: raw) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }
}

extension RemoteModifier {
    static func from(_ flags: NSEvent.ModifierFlags) -> Set<RemoteModifier> {
        var modifiers: Set<RemoteModifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
```

- [ ] **Step 2: Replace app root with AppState and InputRouter**

Replace `Sources/TVShell/TVShellApp.swift` with:

```swift
import SwiftUI

@main
struct TVShellApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            InputRouterView { command in
                appState.handle(command)
            } content: {
                LauncherView()
                    .environmentObject(appState)
            }
            .frame(minWidth: 1280, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
```

- [ ] **Step 3: Run build and observe missing LauncherView**

Run:

```bash
swift build
```

Expected: build fails because `LauncherView` does not exist. This is the intended integration point for the next task.

- [ ] **Step 4: Commit after LauncherView task instead of here**

Do not commit this partial state separately. Continue to Task 7, then commit the runnable UI and input router together.

---

### Task 7: Add Large-Screen Launcher View

**Files:**
- Create: `Sources/TVShell/Launcher/LauncherView.swift`
- Create: `Sources/TVShell/Launcher/AppCardView.swift`

- [ ] **Step 1: Create AppCardView**

Create `Sources/TVShell/Launcher/AppCardView.swift`:

```swift
import SwiftUI

public struct AppCardView: View {
    public let title: String
    public let isFocused: Bool

    public init(title: String, isFocused: Bool) {
        self.title = title
        self.isFocused = isFocused
    }

    public var body: some View {
        VStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(cardFill)
                .overlay(
                    Text(String(title.prefix(1)))
                        .font(.system(size: 82, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                .frame(width: 220, height: 220)
                .shadow(color: isFocused ? .white.opacity(0.35) : .black.opacity(0.25), radius: isFocused ? 38 : 14, x: 0, y: isFocused ? 24 : 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(isFocused ? 0.95 : 0.12), lineWidth: isFocused ? 6 : 1)
                )

            Text(title)
                .font(.system(size: 34, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 260)
        }
        .scaleEffect(isFocused ? 1.12 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isFocused)
        .accessibilityLabel(title)
    }

    private var cardFill: LinearGradient {
        LinearGradient(
            colors: isFocused ? [.blue, .purple, .pink] : [.gray.opacity(0.7), .gray.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
```

- [ ] **Step 2: Create LauncherView**

Create `Sources/TVShell/Launcher/LauncherView.swift`:

```swift
import SwiftUI

public struct LauncherView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.05, blue: 0.09), Color(red: 0.14, green: 0.09, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch appState.activeRuntime {
            case .launcher:
                launcher
            case let .web(app):
                WebAppRuntimeView(app: app)
            case let .native(app):
                NativeRuntimeInterimView(app: app)
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

            Spacer()

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
        return "Last: \(String(describing: command))"
    }
}
```

- [ ] **Step 3: Create interim native runtime view**

Add this interim view at the end of `Sources/TVShell/Launcher/LauncherView.swift`:

```swift
private struct NativeRuntimeInterimView: View {
    let app: TVAppProfile

    var body: some View {
        VStack(spacing: 32) {
            Text(app.name)
                .font(.system(size: 72, weight: .bold))
            Text("Native runtime opens in Task 9. Press Home to return.")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 4: Add interim WebAppRuntimeView**

Create `Sources/TVShell/Runtime/WebAppRuntimeView.swift`:

```swift
import SwiftUI

public struct WebAppRuntimeView: View {
    public let app: TVAppProfile

    public init(app: TVAppProfile) {
        self.app = app
    }

    public var body: some View {
        VStack(spacing: 32) {
            Text(app.name)
                .font(.system(size: 72, weight: .bold))
            Text("Web runtime loads in Task 8. Press Home to return.")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
    }
}
```

- [ ] **Step 5: Run app manually**

Run:

```bash
swift run TVShell
```

Expected:

- Large TV-style launcher appears.
- Left and Right arrow keys move focus between app cards.
- Enter opens the focused card.
- Command-H returns to launcher because it maps to `RemoteCommand.home`.

- [ ] **Step 6: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/TVShell/TVShellApp.swift Sources/TVShell/Input/InputRouter.swift Sources/TVShell/Launcher Sources/TVShell/Runtime/WebAppRuntimeView.swift
git commit -m "feat: add remote-controlled launcher shell"
```

Expected: one commit is created.

---

### Task 8: Add WKWebView Web Runtime

**Files:**
- Modify: `Sources/TVShell/Runtime/WebAppRuntimeView.swift`

- [ ] **Step 1: Replace interim web view with WKWebView runtime**

Replace `Sources/TVShell/Runtime/WebAppRuntimeView.swift` with:

```swift
import SwiftUI
import WebKit

public struct WebAppRuntimeView: NSViewRepresentable {
    public let app: TVAppProfile

    public init(app: TVAppProfile) {
        self.app = app
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userScript = WKUserScript(
            source: Self.remoteBridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")

        if case let .web(url) = app.target {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {}

    public static let remoteBridgeScript = """
    (() => {
      if (window.__tvShellInstalled) return;
      window.__tvShellInstalled = true;

      const style = document.createElement('style');
      style.textContent = `
        :focus {
          outline: 6px solid rgba(255,255,255,.96) !important;
          outline-offset: 8px !important;
        }
        button, a, input, select, textarea, [role="button"], [tabindex] {
          min-height: 44px;
        }
      `;
      document.documentElement.appendChild(style);

      window.tvShellCommand = (command) => {
        const active = document.activeElement;
        const focusables = Array.from(document.querySelectorAll('a, button, input, select, textarea, video, [role="button"], [tabindex]:not([tabindex="-1"])'))
          .filter(el => !el.disabled && el.offsetParent !== null);

        const currentIndex = Math.max(0, focusables.indexOf(active));
        const focusAt = (index) => {
          const next = focusables[Math.max(0, Math.min(index, focusables.length - 1))];
          if (next && next.focus) {
            next.focus({ preventScroll: false });
            next.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
          }
        };

        if (command === 'select') {
          if (active && active.click) active.click();
          return true;
        }
        if (command === 'down' || command === 'right') {
          focusAt(currentIndex + 1);
          return true;
        }
        if (command === 'up' || command === 'left') {
          focusAt(currentIndex - 1);
          return true;
        }
        if (command === 'playPause') {
          const video = document.querySelector('video');
          if (video) {
            if (video.paused) video.play(); else video.pause();
            return true;
          }
        }
        return false;
      };
    })();
    """
}
```

- [ ] **Step 2: Add web command routing to AppState**

Modify `Sources/TVShell/App/AppState.swift` so `handleRuntimeCommand` remains Home-first:

```swift
    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home {
            activeRuntime = .launcher
        }
    }
```

Expected: no functional change yet; this keeps Home reliable while WebKit-specific command injection is wired in a later phase.

- [ ] **Step 3: Run the app manually**

Run:

```bash
swift run TVShell
```

Expected:

- Open YouTube or Apple web app from the launcher.
- Web content loads inside the shell.
- Command-H returns to launcher.

- [ ] **Step 4: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/TVShell/Runtime/WebAppRuntimeView.swift Sources/TVShell/App/AppState.swift
git commit -m "feat: add wkwebview web runtime"
```

Expected: one commit is created.

---

### Task 9: Add Native App Launching

**Files:**
- Create: `Sources/TVShell/Runtime/NativeAppRuntime.swift`
- Create: `Tests/TVShellTests/NativeAppRuntimeTests.swift`
- Modify: `Sources/TVShell/App/AppState.swift`
- Modify: `Sources/TVShell/Launcher/LauncherView.swift`

- [ ] **Step 1: Write failing native runtime tests**

Create `Tests/TVShellTests/NativeAppRuntimeTests.swift`:

```swift
import XCTest
@testable import TVShell

final class NativeAppRuntimeTests: XCTestCase {
    func testNativeLaunchRequestUsesBundleIdentifier() {
        let profile = TVAppProfile(
            name: "Safari",
            target: .nativeApp(bundleIdentifier: "com.apple.Safari"),
            controlMode: .hybridNative
        )

        XCTAssertEqual(NativeLaunchRequest(profile: profile)?.bundleIdentifier, "com.apple.Safari")
    }

    func testWebProfileDoesNotCreateNativeLaunchRequest() {
        let profile = TVAppProfile(
            name: "Apple",
            target: .web(URL(string: "https://www.apple.com")!),
            controlMode: .web
        )

        XCTAssertNil(NativeLaunchRequest(profile: profile))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter NativeAppRuntimeTests
```

Expected: compile fails because `NativeLaunchRequest` does not exist.

- [ ] **Step 3: Implement native runtime**

Create `Sources/TVShell/Runtime/NativeAppRuntime.swift`:

```swift
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

    public func launch(_ profile: TVAppProfile) {
        guard let request = NativeLaunchRequest(profile: profile),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.bundleIdentifier)
        else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
}
```

- [ ] **Step 4: Run native tests**

Run:

```bash
swift test --filter NativeAppRuntimeTests
```

Expected: all `NativeAppRuntimeTests` pass.

- [ ] **Step 5: Launch native app from AppState**

Modify `Sources/TVShell/App/AppState.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var activeRuntime: ActiveRuntime = .launcher
    @Published public var focusedAppID: UUID?
    @Published public var lastCommand: RemoteCommand?
    @Published public var apps: [TVAppProfile]

    private let nativeRuntime = NativeAppRuntime()

    public init(apps: [TVAppProfile] = SeedApps.defaultApps) {
        self.apps = apps
        self.focusedAppID = apps.first?.id
    }

    public func handle(_ command: RemoteCommand) {
        lastCommand = command

        switch activeRuntime {
        case .launcher:
            handleLauncher(command)
        case .web:
            handleRuntimeCommand(command)
        case .native:
            handleRuntimeCommand(command)
        }
    }

    private func handleLauncher(_ command: RemoteCommand) {
        switch command {
        case .left:
            moveFocusedApp(by: -1)
        case .right:
            moveFocusedApp(by: 1)
        case .select:
            openFocusedApp()
        case .home:
            activeRuntime = .launcher
        default:
            break
        }
    }

    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home {
            activeRuntime = .launcher
        }
    }

    private func moveFocusedApp(by offset: Int) {
        guard let focusedAppID, let index = apps.firstIndex(where: { $0.id == focusedAppID }) else {
            self.focusedAppID = apps.first?.id
            return
        }
        let nextIndex = min(max(index + offset, 0), apps.count - 1)
        self.focusedAppID = apps[nextIndex].id
    }

    private func openFocusedApp() {
        guard let app = apps.first(where: { $0.id == focusedAppID }) else {
            return
        }
        switch app.target {
        case .web:
            activeRuntime = .web(app)
        case .nativeApp:
            activeRuntime = .native(app)
            nativeRuntime.launch(app)
        }
    }
}
```

- [ ] **Step 6: Run manual native app test**

Run:

```bash
swift run TVShell
```

Expected:

- Move focus to Safari.
- Press Enter.
- Safari launches or activates.
- TV Shell still has an interim native runtime view if it remains visible.
- Relaunch TV Shell and Command-H returns to launcher from internal runtime states.

- [ ] **Step 7: Run all tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add Sources/TVShell/Runtime/NativeAppRuntime.swift Sources/TVShell/App/AppState.swift Tests/TVShellTests/NativeAppRuntimeTests.swift
git commit -m "feat: launch native macos apps from shell"
```

Expected: one commit is created.

---

### Task 10: Add Accessibility Permission and Scanner

**Files:**
- Create: `Sources/TVShell/Runtime/AccessibilityScanner.swift`
- Create: `Sources/TVShell/Settings/PermissionStatusView.swift`
- Modify: `Sources/TVShell/Launcher/LauncherView.swift`

- [ ] **Step 1: Implement AccessibilityScanner**

Create `Sources/TVShell/Runtime/AccessibilityScanner.swift`:

```swift
import ApplicationServices
import AppKit
import Foundation

public struct AccessibilityElementSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: String
    public let title: String

    public init(id: UUID = UUID(), role: String, title: String) {
        self.id = id
        self.role = role
        self.title = title
    }
}

public enum AccessibilityScanner {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static func requestTrustPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func frontmostApplicationElements(limit: Int = 40) -> [AccessibilityElementSnapshot] {
        guard isTrusted else {
            return []
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            return []
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return children(of: appElement, limit: limit)
    }

    private static func children(of element: AXUIElement, limit: Int) -> [AccessibilityElementSnapshot] {
        var output: [AccessibilityElementSnapshot] = []
        collect(element, into: &output, limit: limit)
        return output
    }

    private static func collect(_ element: AXUIElement, into output: inout [AccessibilityElementSnapshot], limit: Int) {
        if output.count >= limit {
            return
        }

        let role = stringAttribute(element, kAXRoleAttribute as String)
        let title = stringAttribute(element, kAXTitleAttribute as String)

        if role.isEmpty == false || title.isEmpty == false {
            output.append(AccessibilityElementSnapshot(role: role, title: title))
        }

        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return
        }

        for child in children {
            collect(child, into: &output, limit: limit)
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return ""
        }
        return value as? String ?? ""
    }
}
```

- [ ] **Step 2: Create permission status view**

Create `Sources/TVShell/Settings/PermissionStatusView.swift`:

```swift
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

            Button("Open Accessibility Prompt") {
                AccessibilityScanner.requestTrustPrompt()
            }
            .font(.system(size: 26, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(40)
    }
}
```

- [ ] **Step 3: Show permission status on launcher**

Add `PermissionStatusView()` near the bottom of the launcher `VStack` in `Sources/TVShell/Launcher/LauncherView.swift`, above the hint text:

```swift
PermissionStatusView()
```

- [ ] **Step 4: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 5: Run app and check permission UI**

Run:

```bash
swift run TVShell
```

Expected:

- Launcher shows Accessibility permission status.
- Button prompts for Accessibility permission.
- App remains usable even if permission is denied.

- [ ] **Step 6: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/TVShell/Runtime/AccessibilityScanner.swift Sources/TVShell/Settings/PermissionStatusView.swift Sources/TVShell/Launcher/LauncherView.swift
git commit -m "feat: add accessibility permission status"
```

Expected: one commit is created.

---

### Task 11: Add Remote Learning Screen

**Files:**
- Create: `Sources/TVShell/Settings/RemoteLearningView.swift`
- Modify: `Sources/TVShell/App/AppState.swift`
- Modify: `Sources/TVShell/Launcher/SeedApps.swift`
- Modify: `Sources/TVShell/Launcher/LauncherView.swift`

- [ ] **Step 1: Add settings seed app**

Modify `Sources/TVShell/Launcher/SeedApps.swift`:

```swift
import Foundation

public enum SeedApps {
    public static let defaultApps: [TVAppProfile] = [
        TVAppProfile(
            name: "YouTube",
            target: .web(URL(string: "https://www.youtube.com/tv")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Apple",
            target: .web(URL(string: "https://www.apple.com")!),
            controlMode: .web
        ),
        TVAppProfile(
            name: "Safari",
            target: .nativeApp(bundleIdentifier: "com.apple.Safari"),
            controlMode: .hybridNative
        ),
        TVAppProfile(
            name: "Remote",
            target: .web(URL(string: "tv-shell://remote-learning")!),
            controlMode: .web
        )
    ]
}
```

- [ ] **Step 2: Add settings runtime case**

Modify `Sources/TVShell/Runtime/AppRuntime.swift`:

```swift
public enum RuntimeKind: String, Codable, Equatable, Sendable {
    case launcher
    case web
    case native
    case remoteLearning
}
```

Replace `ActiveRuntime` in the same file with:

```swift
public enum ActiveRuntime: Equatable, Sendable {
    case launcher
    case web(TVAppProfile)
    case native(TVAppProfile)
    case remoteLearning
}
```

- [ ] **Step 3: Route Remote card to RemoteLearning**

Modify `openFocusedApp()` in `Sources/TVShell/App/AppState.swift`:

```swift
    private func openFocusedApp() {
        guard let app = apps.first(where: { $0.id == focusedAppID }) else {
            return
        }
        switch app.target {
        case let .web(url) where url.scheme == "tv-shell" && url.host == "remote-learning":
            activeRuntime = .remoteLearning
        case .web:
            activeRuntime = .web(app)
        case .nativeApp:
            activeRuntime = .native(app)
            nativeRuntime.launch(app)
        }
    }
```

Also update `handle(_:)` to include `.remoteLearning`:

```swift
        switch activeRuntime {
        case .launcher:
            handleLauncher(command)
        case .web, .native, .remoteLearning:
            handleRuntimeCommand(command)
        }
```

Replace `handleRuntimeCommand(_:)` in `Sources/TVShell/App/AppState.swift` with:

```swift
    private func handleRuntimeCommand(_ command: RemoteCommand) {
        if command == .home {
            activeRuntime = .launcher
            return
        }

        if activeRuntime == .remoteLearning, command == .select {
            AccessibilityScanner.requestTrustPrompt()
        }
    }
```

- [ ] **Step 4: Create RemoteLearningView**

Create `Sources/TVShell/Settings/RemoteLearningView.swift`:

```swift
import SwiftUI

public struct RemoteLearningView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("Remote Setup")
                .font(.system(size: 72, weight: .bold))

            Text("Press buttons on your remote. The shell shows the normalized command it sees. Use Home to return.")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: 900, alignment: .leading)

            Text(appState.lastCommand.map { "Last command: \(String(describing: $0))" } ?? "Waiting for remote input")
                .font(.system(size: 42, weight: .semibold))
                .padding(.horizontal, 34)
                .padding(.vertical, 24)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            PermissionStatusView()

            Spacer()
        }
        .foregroundStyle(.white)
        .padding(96)
    }
}
```

- [ ] **Step 5: Render RemoteLearningView**

Modify the `switch appState.activeRuntime` in `Sources/TVShell/Launcher/LauncherView.swift`:

```swift
            switch appState.activeRuntime {
            case .launcher:
                launcher
            case let .web(app):
                WebAppRuntimeView(app: app)
            case let .native(app):
                NativeRuntimeInterimView(app: app)
            case .remoteLearning:
                RemoteLearningView()
            }
```

- [ ] **Step 6: Run manual remote learning test**

Run:

```bash
swift run TVShell
```

Expected:

- Move focus to Remote.
- Press Enter.
- Remote Setup screen opens.
- Arrow keys, Enter, Escape, Space, Command-H show command changes where mapped.
- Enter on the Remote Setup screen opens the Accessibility permission prompt.
- Command-H returns to launcher.

- [ ] **Step 7: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

Run:

```bash
git add Sources/TVShell/Settings/RemoteLearningView.swift Sources/TVShell/App/AppState.swift Sources/TVShell/Launcher/SeedApps.swift Sources/TVShell/Launcher/LauncherView.swift Sources/TVShell/Runtime/AppRuntime.swift
git commit -m "feat: add remote learning screen"
```

Expected: one commit is created.

---

### Task 12: Add Full-Screen Window Manager

**Files:**
- Create: `Sources/TVShell/App/ShellWindowManager.swift`
- Modify: `Sources/TVShell/TVShellApp.swift`

- [ ] **Step 1: Create ShellWindowManager**

Create `Sources/TVShell/App/ShellWindowManager.swift`:

```swift
import AppKit
import SwiftUI

public struct ShellWindowConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 1280, height: 720)
    }
}
```

- [ ] **Step 2: Attach configurator to root app**

Modify the root view inside `Sources/TVShell/TVShellApp.swift`:

```swift
                LauncherView()
                    .environmentObject(appState)
                    .background(ShellWindowConfigurator())
```

- [ ] **Step 3: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 4: Run manual window test**

Run:

```bash
swift run TVShell
```

Expected:

- Window has hidden title bar styling.
- macOS full-screen button works.
- Launcher remains readable after entering full-screen.

- [ ] **Step 5: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/TVShell/App/ShellWindowManager.swift Sources/TVShell/TVShellApp.swift
git commit -m "feat: configure tv shell window"
```

Expected: one commit is created.

---

### Task 13: Phase 1 Verification

**Files:**
- No new files.

- [ ] **Step 1: Run unit tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build release**

Run:

```bash
swift build -c release
```

Expected: release build succeeds.

- [ ] **Step 3: Manual launcher test**

Run:

```bash
swift run TVShell
```

Expected:

- Large launcher opens.
- Focus is obvious.
- Left and Right move through cards.
- Enter opens a web card.
- Command-H returns to launcher.
- Remote setup screen displays last normalized command.

- [ ] **Step 4: Manual native app test**

Run:

```bash
swift run TVShell
```

Expected:

- Focus Safari card.
- Press Enter.
- Safari launches or activates.
- TV Shell does not crash.

- [ ] **Step 5: Manual Accessibility permission test**

Run:

```bash
swift run TVShell
```

Expected:

- Launcher shows Accessibility permission status.
- Permission prompt opens when selected with mouse for this phase.
- Denying permission leaves launcher usable.

- [ ] **Step 6: Commit verification notes**

Create `docs/superpowers/plans/2026-07-05-remote-first-tv-shell-phase-1-verification.md`:

```markdown
# Remote-First TV Shell Phase 1 Verification

## Automated

- `swift test`: passing
- `swift build -c release`: passing

## Manual

- Launcher opens: passing
- Directional focus moves with keyboard arrows: passing
- Select opens focused card: passing
- Home returns to launcher from internal runtimes: passing
- Web runtime loads WKWebView content: passing
- Native Safari launch: passing
- Accessibility permission status renders: passing

## Known Phase 1 Limits

- CoreHID device-specific remote discovery is planned for Phase 2.
- Native app deep control currently starts with permission status and AX scanning foundation.
- Full AVPlayer media runtime is planned for Phase 2.
```

- [ ] **Step 7: Commit verification notes**

Run:

```bash
git add docs/superpowers/plans/2026-07-05-remote-first-tv-shell-phase-1-verification.md
git commit -m "test: record phase 1 verification"
```

Expected: one commit is created.

---

## Self-Review

### Spec Coverage

- Remote-first input normalization: Tasks 2, 3, 6, 11.
- Android TV remote setup path: Tasks 2, 3, 11.
- Focus system: Task 4 and launcher behavior in Task 7.
- Home reliability: Tasks 5, 7, 8, 11.
- Launcher: Tasks 5, 7, 12.
- Web runtime: Task 8.
- Native app launching: Task 9.
- Accessibility permission and initial scan: Task 10.
- Large-screen readability: Tasks 7, 12.
- Verification: Task 13.

### Type Consistency

- `RemoteCommand` is defined in Task 2 and used by AppState/InputRouter in Tasks 5 and 6.
- `TVAppProfile`, `LaunchTarget`, `ControlMode`, and `ActiveRuntime` are defined in Task 5 and extended in Task 11.
- `FocusEngine`, `FocusNode`, `FocusID`, and `FocusDirection` are contained in Task 4.

### Phase 1 Acceptance

Phase 1 is complete when `swift test` and `swift build -c release` pass, and the manual verification confirms that the shell can be navigated by remote-like keyboard input, can return Home from internal runtimes, can open web content, can launch Safari, and can show Accessibility permission status.
