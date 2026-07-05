# Remote-First macOS TV Shell Design

## Goal

Build a macOS TV shell that is primarily controlled by remotes, especially Android TV remotes, with a large-screen launcher, smooth focus animation, app launching, web app control, media control, and optional deep control of native macOS apps through Accessibility permissions.

The first implementation milestone is not a beautiful launcher by itself. The first milestone is a reliable remote-control foundation that makes the launcher, settings, web apps, media apps, and native macOS apps usable from a sofa.

## Product Principle

Remote control is the core product. Every screen and runtime must answer these questions before visual polish is considered complete:

- What is focused now?
- What happens when the user presses Up, Down, Left, Right, OK, Back, Home, Menu, Play/Pause, Volume Up, and Volume Down?
- Can the user recover if focus is lost?
- Can the user return to the TV shell from this state?
- Does the same remote behavior work with keyboard arrows and common Android TV remotes?

## Technical Stack

- Swift and SwiftUI for the TV-scale interface, focus visuals, launcher, settings, and animation.
- AppKit for full-screen window management, event monitoring, menu-bar hiding, native app activation, and lower-level macOS integration.
- CoreHID for identifying HID remotes when macOS exposes them as external input devices.
- NSEvent for app-local keyboard and remote-like key input.
- CGEvent for optional synthetic key events sent to native apps.
- Accessibility APIs through AXUIElement for optional deep control of native apps.
- WKWebView for web apps that need remote-controllable focus, zoom, navigation, and video control.
- AVKit or AVPlayer for first-class media playback.

## Remote-First Architecture

```text
TVShellApp
├─ InputRouter
│  ├─ KeyboardEventSource
│  ├─ HIDRemoteEventSource
│  ├─ MediaKeyEventSource
│  ├─ RemoteLearningController
│  └─ RemoteMappingStore
├─ RemoteCommandDispatcher
│  ├─ LauncherCommandHandler
│  ├─ WebRuntimeCommandHandler
│  ├─ MediaRuntimeCommandHandler
│  ├─ NativeKeyboardCommandHandler
│  ├─ NativeAccessibilityCommandHandler
│  └─ SystemCommandHandler
├─ FocusEngine
│  ├─ FocusNodeRegistry
│  ├─ DirectionalMovementResolver
│  ├─ FocusHistory
│  ├─ FocusRecovery
│  └─ FocusAnimationState
├─ RuntimeLayer
│  ├─ LauncherRuntime
│  ├─ WebAppRuntime
│  ├─ MediaRuntime
│  └─ NativeAppRuntime
├─ AppRegistry
├─ Settings
└─ ShellWindowManager
```

Input flows in one direction:

```text
Physical remote or keyboard
→ raw macOS input event
→ normalized RemoteCommand
→ active runtime command handler
→ focus movement, app action, media action, or system action
→ visual and haptic-equivalent feedback
```

## Normalized Remote Commands

All remotes map into one command model:

```swift
enum RemoteCommand: Equatable, Codable {
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

The app must never let raw key codes leak into UI code. UI code only receives `RemoteCommand`.

## Required Android TV Remote Mapping

Default mappings:

| Android TV remote input | RemoteCommand |
| --- | --- |
| D-pad Up | `up` |
| D-pad Down | `down` |
| D-pad Left | `left` |
| D-pad Right | `right` |
| OK / Center / Enter | `select` |
| Back | `back` |
| Home | `home` |
| Menu | `menu` |
| Play/Pause | `playPause` |
| Rewind | `rewind` |
| Fast Forward | `fastForward` |
| Volume Up | `volumeUp` |
| Volume Down | `volumeDown` |
| Mute | `mute` |

Because macOS and remote vendors expose keys differently, the product must include a Remote Learning screen. The user can select a command, press the physical button, and save the observed key code, HID usage, or media key event.

## Input Capture Strategy

### Local Shell Input

When the TV shell is focused, use local `NSEvent` monitoring and SwiftUI/AppKit key handling. This covers keyboard arrows, Enter, Escape, Space, and many remotes that appear as keyboards.

### Global Remote Input

When another app is focused, use global event monitoring where permitted. macOS may require Accessibility and Input Monitoring permissions for global key events. The app must show a clear permission status screen and never silently fail.

### HID Remote Input

Use CoreHID as an advanced path for remotes that expose HID usage data. This is important for Android TV remotes whose Back, Home, Menu, and media buttons may not arrive as normal keyboard keys.

### Media Keys

Support play/pause, volume, mute, fast-forward, and rewind as first-class commands. In the shell these commands route to the active runtime. In native apps they can be sent as system media key events when permitted.

## Focus Engine

The FocusEngine is independent from SwiftUI's built-in focus state. SwiftUI focus can be used for fields and native controls, but the TV shell needs its own directional model.

Each focusable item registers:

```swift
struct FocusNode {
    let id: FocusID
    let rect: CGRect
    let group: FocusGroupID
    let priority: Int
    let acceptsSelect: Bool
    let acceptsLongPress: Bool
}
```

Directional movement rules:

- Prefer items in the requested direction.
- Prefer the item with the closest projected centerline.
- Keep movement inside the current row, grid, modal, or overlay unless an edge rule allows escape.
- Remember the last focused item in each screen and each row.
- If focus disappears, recover to the nearest visible item or the screen default.

Visual focus requirements:

- Focused items must be readable from sofa distance.
- Focused items scale up, lift, gain shadow, and show a clear focus ring or glow.
- Focus movement must animate smoothly.
- Focus feedback must remain visible on 1080p, 2K, 4K, and larger displays.

## Command Dispatch by Runtime

### Launcher Runtime

| Command | Behavior |
| --- | --- |
| Up/Down/Left/Right | Move focus through rows, cards, nav, and settings |
| Select | Open focused app, button, or settings item |
| Back | Close modal, leave settings, or move to previous launcher level |
| Home | Return to launcher root |
| Menu | Open focused item context menu |
| Play/Pause | If focused card has preview media, toggle preview |
| Volume | Adjust system volume or configured output |

### Web App Runtime

Web apps run inside WKWebView whenever possible because that allows real remote control.

| Command | Behavior |
| --- | --- |
| Up/Down/Left/Right | Move DOM focus or scroll in TV mode |
| Select | Click focused element or play focused video |
| Back | Browser history back, close overlay, or return to shell |
| Home | Return to shell |
| Menu | Show runtime menu: zoom, reload, URL, remote mode |
| Play/Pause | Control first visible video element |
| Rewind/FastForward | Seek active video |
| Volume | App volume or system volume |

Web mode should inject a remote bridge where allowed:

- CSS for larger text, bigger hit targets, and TV-safe spacing.
- JavaScript to find focusable elements.
- JavaScript to click, scroll, navigate history, and control HTML video.
- A fallback scroll mode when DOM focus cannot be inferred.

### Media Runtime

Media apps use AVPlayer or AVKit when the target is a media URL or file.

| Command | Behavior |
| --- | --- |
| Left/Right | Seek backward/forward |
| Up/Down | Show controls or adjust subtitle/audio menus |
| Select | Toggle controls or activate focused control |
| Back | Hide controls, then return to launcher |
| Home | Return to shell |
| Play/Pause | Toggle playback |
| Volume | Adjust playback or system volume |

### Native App Runtime

Native macOS apps support three control modes.

#### Basic Keyboard Mode

Launch the app, activate it, optionally make it full-screen, and send keyboard-like commands:

- Directions become arrow keys.
- Select becomes Enter or Space.
- Back becomes Escape or Command-[ depending on profile.
- Home returns to the TV shell.
- Play/Pause maps to media key or Space depending on profile.

#### Accessibility Deep Control Mode

If the user grants Accessibility permission, scan the frontmost app's accessibility tree and build a TV focus layer over accessible elements.

Supported behavior:

- Discover buttons, text fields, lists, tables, menus, tabs, sliders, and windows.
- Draw an optional shell overlay focus ring around the selected accessible element.
- Move focus spatially between accessible elements with directional commands.
- Select performs the best available AX action, usually press, confirm, or focus.
- Back closes popovers, cancels dialogs, sends Escape, or returns to the previous accessibility focus group.
- Menu shows available AX actions for the selected element.
- Home always returns to the TV shell.

This mode should be described as "deep control" rather than "perfect control". Some apps do not expose complete Accessibility data, and some custom-rendered interfaces cannot be fully controlled through AXUIElement.

#### Hybrid Mode

Hybrid mode is the default for native apps:

1. Try Accessibility deep control when permission and usable elements are available.
2. Fall back to keyboard control when Accessibility data is missing or stale.
3. Use per-app custom mappings when the user has configured them.

## Home and Back Must Be Reliable

Home is the escape hatch. It must work from:

- Launcher.
- Settings.
- App management.
- Web apps.
- Media playback.
- Native app keyboard mode.
- Native app Accessibility mode.
- Permission screens.
- Error screens.

If a remote's physical Home button is intercepted by the system and not observable, the Remote Learning screen must let the user bind another button or long-press combination as Shell Home.

Back behavior is context-sensitive:

1. Close transient overlay.
2. Return to previous screen or focus group.
3. Browser history back in WebRuntime.
4. Hide media controls or exit media.
5. Send native Escape or Accessibility cancel.
6. If no local back action exists, show a lightweight return-to-shell prompt.

## App Profiles

Each app has a remote profile:

```swift
struct TVAppProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var kind: TVAppKind
    var launchTarget: LaunchTarget
    var icon: IconSource
    var category: String
    var isVisibleOnHome: Bool
    var launchFullscreen: Bool
    var displayScale: DisplayScale
    var controlMode: ControlMode
    var remoteMappingProfileID: UUID?
}

enum ControlMode: String, Codable {
    case automatic
    case web
    case media
    case nativeKeyboard
    case nativeAccessibility
    case hybridNative
    case custom
}
```

The default should be:

- Web URL: `web`
- Media file or stream: `media`
- Native app: `hybridNative`

## Settings Required for Remote Priority

Settings must include:

- Remote setup wizard.
- Remote learning and remapping.
- Test screen showing live raw input and normalized command.
- Long-press configuration.
- Repeat delay and repeat speed.
- Home fallback binding.
- Back behavior preference.
- Per-app control mode.
- Per-app key mapping.
- Accessibility permission status.
- Input Monitoring permission status.
- Overlay focus ring on/off.
- UI scale: Auto, 100%, 125%, 150%, 200%.

## Permission UX

Permissions are part of the product, not an afterthought.

The app should show a large-screen permission checklist:

- Accessibility: needed for deep native app control and some global input monitoring.
- Input Monitoring: needed for observing certain global key events.
- Automation: optional, only if later integrations need Apple Events.

When permission is missing, the app should still work in launcher, web, media, and local keyboard modes. Native app deep control should show a clear disabled state with an action to open System Settings.

## MVP Scope

The first milestone should deliver:

1. Full-screen macOS shell.
2. InputRouter that normalizes keyboard arrows, Enter, Escape, Space, and common media keys.
3. Remote Learning screen that records unknown remote keys.
4. FocusEngine for launcher/settings navigation.
5. Launcher with large cards and visible focus.
6. WebAppRuntime with remote navigation, Back, Home, zoom, and video play/pause.
7. NativeAppRuntime with app launching and keyboard control.
8. Accessibility permission flow.
9. NativeAppRuntime hybrid mode with initial AX element scanning and Select action.
10. Reliable Home return path from every runtime.

Visual polish is still required, but it must be layered on top of working remote semantics.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Android TV remotes expose different key codes | Add Remote Learning and per-device mapping profiles |
| Home button may be intercepted by macOS or the remote driver | Allow custom Home binding and long-press fallback |
| Native apps expose incomplete Accessibility trees | Use Hybrid Mode and per-app profiles |
| Global input requires permissions | Provide permission checklist and degraded modes |
| Focus can be lost during animations or app transitions | Build FocusRecovery into FocusEngine |
| Web pages have unpredictable DOM structures | Provide DOM focus mode plus scroll mode fallback |
| 4K UI and blur effects may hurt performance | Keep motion tokens centralized and profile performance early |

## Success Criteria

- A user can set up an Android TV remote without touching the keyboard after first launch.
- Directional navigation works consistently in launcher, settings, web runtime, media runtime, and native app control overlay.
- OK, Back, Home, Menu, Play/Pause, and Volume commands have defined behavior in every runtime.
- Home reliably returns to the TV shell or provides a configured fallback command.
- Web apps such as YouTube-style pages can be opened, navigated, played/paused, and returned from using the remote.
- Native macOS apps can be launched, brought forward, controlled with keyboard fallback, and optionally controlled more deeply with Accessibility.
- UI remains readable and focus remains obvious on 1080p, 2K, 4K, and larger displays.
