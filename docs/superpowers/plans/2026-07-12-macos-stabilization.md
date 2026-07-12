# TVShell macOS Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the current macOS playback and focus defects, add Bing wallpaper and danmaku controls, and prepare stable behavior contracts before branding and cross-platform extraction.

**Architecture:** Keep platform behavior in focused pure state types and isolate WebKit automation in an AniGamer bridge. Views render the state and forward `RemoteCommand`; persistent settings remain owned by `AppState`. Every behavior enters through a failing `TVShellChecks` assertion before production code changes.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit, AVFoundation, URLSession, TVShellChecks

## Global Constraints

- Work directly on the user-approved `main` branch and push each completed batch to `origin main`.
- Preserve AniGamer advertising, authentication, entitlement, age, and region behavior; do not extract streams or manipulate media time through page internals.
- UI copy is Traditional Chinese and uses the existing tvOS 18 design system.
- Existing CSS1, BT, Dandanplay, credentials, history, and settings behavior must remain compatible.
- `swift run TVShellChecks`, `swift build -c release --product TVShell`, and `git diff --check` must pass before completion.

---

### Task 1: AniGamer Remote Bridge and Age Prompt

**Files:**
- Create: `Sources/TVShellCore/Anime/AniGamerRemoteBridge.swift`
- Modify: `Sources/TVShellCore/Anime/AniGamerOfficialPlayerView.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Consumes: `RemoteCommand`, `WKWebView`, `AniGamerOfficialPlayerView.Coordinator`
- Produces: `AniGamerRemoteAction`, `AniGamerRemoteBridge.action(for:)`, and `AniGamerOfficialPageScript.source`

- [ ] **Step 1: Write failing checks for every remote action and the restricted page script**

Add assertions equivalent to:

```swift
try expect(AniGamerRemoteBridge.action(for: .left) == .key(code: 123, characters: NSLeftArrowFunctionKey), "AniGamer left seeks through the official player")
try expect(AniGamerRemoteBridge.action(for: .right) == .key(code: 124, characters: NSRightArrowFunctionKey), "AniGamer right seeks through the official player")
try expect(AniGamerRemoteBridge.action(for: .up) == .volume(step: 0.0625), "AniGamer up raises volume")
try expect(AniGamerRemoteBridge.action(for: .down) == .volume(step: -0.0625), "AniGamer down lowers volume")
try expect(AniGamerRemoteBridge.action(for: .select) == .key(code: 49, characters: 32), "AniGamer OK activates play")
try expect(AniGamerRemoteBridge.action(for: .menu) == .key(code: 3, characters: 102), "AniGamer Menu toggles fullscreen")
try expect(AniGamerOfficialPageScript.source.contains("年齡") && AniGamerOfficialPageScript.source.contains("click()"), "AniGamer acknowledges the visible age prompt")
try expect(AniGamerOfficialPageScript.source.contains("currentTime") == false, "AniGamer script never manipulates playback position")
```

- [ ] **Step 2: Run the checks and verify the new bridge symbols fail to compile**

Run: `swift run TVShellChecks`

Expected: compilation fails because `AniGamerRemoteBridge` and `AniGamerOfficialPageScript` do not exist.

- [ ] **Step 3: Implement the pure action mapping and restricted prompt script**

Create these public shapes:

```swift
public enum AniGamerRemoteAction: Equatable, Sendable {
    case key(code: UInt16, characters: Int)
    case volume(step: Double)
    case exit
    case none
}

public enum AniGamerRemoteBridge {
    public static func action(for command: RemoteCommand) -> AniGamerRemoteAction
}

public enum AniGamerOfficialPageScript {
    public static let source: String
}
```

The script may find visible buttons whose normalized text contains `年齡`, `我已年滿`, or `進入`; it clicks at most one visible matching button once and records a DOM marker. It must not query ad controls, video URLs, entitlement endpoints, or `HTMLMediaElement.currentTime`.

- [ ] **Step 4: Connect actions to the WebView and verify focus fallback**

`AniGamerOfficialPlayerView.Coordinator` sends mapped key events, changes system output volume for `.volume`, evaluates only the age-prompt script after navigation, and keeps the existing two-stage Escape/Back exit. If the page does not accept a key, OK enters the existing virtual-cursor path instead of mutating the video element.

- [ ] **Step 5: Run checks and commit**

Run: `swift run TVShellChecks && git diff --check`

Expected: `TVShellChecks passed` and no whitespace errors.

Commit: `fix: restore AniGamer remote controls`

### Task 2: Anime Source Navigation and Official YouTube Scrolling

**Files:**
- Create: `Sources/TVShellCore/Anime/AnimeSourceNavigationState.swift`
- Modify: `Sources/TVShellCore/Anime/AnimeRuntimeView.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Produces: `AnimeSourceNavigationState`, `move(_:)`, `enterContent()`, `enterNavigation()`
- Consumes: `AnimeOfficialSourcesState`, `ScrollViewReader`

- [ ] **Step 1: Add failing reducer and source-contract checks**

```swift
var navigation = AnimeSourceNavigationState(sourceCount: 3)
navigation.move(.right)
try expect(navigation.focusedSourceIndex == 1, "anime source navigation moves right")
navigation.move(.left)
navigation.move(.left)
try expect(navigation.focusedSourceIndex == 0, "anime source navigation clamps left")
try expect(animeRuntime.contains("official-youtube-\(index)"), "official YouTube results have stable scroll IDs")
try expect(animeRuntime.contains("scrollProxy.scrollTo(\"official-youtube-"), "official YouTube follows focus")
```

- [ ] **Step 2: Run checks and observe the missing reducer/scroll IDs**

Run: `swift run TVShellChecks`

Expected: failure on `AnimeSourceNavigationState` or official YouTube scroll assertions.

- [ ] **Step 3: Implement navigation and scrolling**

The top capsule owns an explicit focus region. Up from the first content row calls `enterNavigation()`, left/right changes source with clamped boundaries, and down calls `enterContent()`. Wrap the official results view in `ScrollViewReader`; assign `official-anigamer-<index>` and `official-youtube-<index>` IDs and scroll the selected source's focused item to `.center`.

- [ ] **Step 4: Verify and commit**

Run: `swift run TVShellChecks && git diff --check`

Commit: `fix: make anime source navigation focusable`

### Task 3: Playback Overlay and Volume Policy

**Files:**
- Create: `Sources/TVShellCore/Runtime/PlaybackOverlayState.swift`
- Create: `Sources/TVShellCore/Runtime/VolumeController.swift`
- Modify: `Sources/TVShellCore/Anime/AnimeRuntimeView.swift`
- Modify: `Sources/TVShellCore/Bilibili/BilibiliRuntimeView.swift`
- Modify: `Sources/TVShellCore/YouTube/YouTubeRuntimeView.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Produces: `PlaybackOverlayState.registerInput(at:)`, `isVisible(at:)`, and `VolumeControlling.adjust(by:)`

- [ ] **Step 1: Add failing tests for HUD timeout, clock hiding, and volume clamps**

```swift
var overlay = PlaybackOverlayState(autoHideInterval: 3)
overlay.registerInput(at: Date(timeIntervalSince1970: 10))
try expect(overlay.isVisible(at: Date(timeIntervalSince1970: 12)), "HUD remains visible before timeout")
try expect(overlay.isVisible(at: Date(timeIntervalSince1970: 14)) == false, "HUD hides after inactivity")
try expect(VolumeLevel(0.98).adjusted(by: 0.1).value == 1, "volume clamps to one")
try expect(VolumeLevel(0.02).adjusted(by: -0.1).value == 0, "volume clamps to zero")
```

- [ ] **Step 2: Run checks and verify failure**

Run: `swift run TVShellChecks`

- [ ] **Step 3: Implement shared overlay and volume state**

All anime playback entry points hide `TVStatusClockOverlay`. Remote input shows the HUD and schedules auto-hide after three seconds. Up/down call the platform volume adapter; if unavailable they adjust the active player's volume. Exiting or failing playback restores the clock exactly once.

- [ ] **Step 4: Verify and commit**

Run: `swift run TVShellChecks && git diff --check`

Commit: `fix: unify playback HUD and volume controls`

### Task 4: Native Official YouTube Presentation

**Files:**
- Create: `Sources/TVShellCore/Anime/OfficialYouTubeAnimeView.swift`
- Modify: `Sources/TVShellCore/Anime/AnimeRuntimeView.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Consumes: `[YouTubeVideo]`, `YouTubePlayerView`, `TVOSMediaVideoCard`, `TVOS18PlayerHUD`
- Produces: native official-channel browse, detail, and player route

- [ ] **Step 1: Add failing view-contract checks**

Assert the new view contains `TVOSMediaVideoCard`, a native detail section, `YouTubePlayerView`, and `TVOS18PlayerHUD`, and contains no `youtube.com/watch` navigation.

- [ ] **Step 2: Run checks and verify the view is absent**

Run: `swift run TVShellChecks`

- [ ] **Step 3: Implement the native route**

Render Muse and Ani-One results as TVShell cards, open a native metadata/detail screen, and present the supported embed player behind the shared HUD. Preserve YouTube advertisements and embed restrictions. Back returns player → detail → result grid.

- [ ] **Step 4: Verify and commit**

Run: `swift run TVShellChecks && git diff --check`

Commit: `feat: add native official YouTube anime UI`

### Task 5: Bing Daily Wallpaper

**Files:**
- Create: `Sources/TVShellCore/Wallpaper/BingWallpaperProvider.swift`
- Modify: `Sources/TVShellCore/Wallpaper/WallpaperSource.swift`
- Modify: `Sources/TVShellCore/App/AppState.swift`
- Modify: `Sources/TVShellCore/Settings/SettingsView.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Produces: `BingWallpaperMetadata`, `BingWallpaperProvider.fetch()`, `.bingDaily` wallpaper source

- [ ] **Step 1: Add failing metadata, URL, and cache fallback tests**

Use a local Bing JSON fixture with `/th?id=OHR.Test_1920x1080.jpg`, copyright, and date. Assert the provider resolves `https://www.bing.com/th?id=OHR.Test_1920x1080.jpg`, writes metadata atomically, and returns the prior cached file when the next fetch throws.

- [ ] **Step 2: Run checks and verify failure**

Run: `swift run TVShellChecks`

- [ ] **Step 3: Implement provider and settings selection**

Fetch `https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1`, download the resolved image, keep attribution, and preserve the last valid cache. Add Bing Daily to wallpaper cycling and the settings value.

- [ ] **Step 4: Verify and commit**

Run: `swift run TVShellChecks && git diff --check`

Commit: `feat: add Bing daily wallpaper`

### Task 6: Control Center Danmaku Controls

**Files:**
- Create: `Sources/TVShellCore/ControlCenter/ControlCenterDanmakuState.swift`
- Modify: `Sources/TVShellCore/ControlCenter/ControlCenterView.swift`
- Modify: `Sources/TVShellCore/App/AppState.swift`
- Modify: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Consumes: `DanmakuDisplaySettings`
- Produces: focusable size, speed, opacity, density, and visibility rows

- [ ] **Step 1: Add failing navigation and adjustment checks**

Assert the five rows appear in visual order, top/bottom clamp, left/right use existing `adjusted*` methods, and every change persists through `AppSettingsStore`.

- [ ] **Step 2: Run checks and verify failure**

Run: `swift run TVShellChecks`

- [ ] **Step 3: Implement the rows and AppState commands**

Use `TVOS18SettingsRow` styling inside Control Center. Post a compact Traditional-Chinese value message after each change and update the shared environment settings immediately.

- [ ] **Step 4: Verify and commit**

Run: `swift run TVShellChecks && git diff --check`

Commit: `feat: adjust danmaku from control center`

### Task 7: Phase Verification and Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-07-12-macos-stabilization.md`

**Interfaces:**
- Produces: verified Phase 1 baseline for branding, Bilibili migration, app SDK, Android, and Windows plans

- [ ] **Step 1: Update user documentation**

Document AniGamer remote commands, official-source navigation, HUD timeout, volume, Bing attribution/cache, and Control Center danmaku controls. State that AniGamer advertising and entitlement are not bypassed.

- [ ] **Step 2: Run full verification**

Run:

```bash
git diff --check
swift run TVShellChecks
swift build -c release --product TVShell
```

Expected: no whitespace errors, `TVShellChecks passed`, and release build exit code 0.

- [ ] **Step 3: Commit and push**

Commit: `docs: document TVShell playback and wallpaper controls`

Run: `git push origin main`

Expected: `main` updates successfully and `git status --short --branch` shows no divergence.

