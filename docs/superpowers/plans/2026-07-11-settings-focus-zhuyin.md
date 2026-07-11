# Settings Focus and Zhuyin Keyboard Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Settings navigation follow its visible order without wrapping, and replace the Zhuyin keyboard with the standard Taiwan Da-Qian layout and spatially natural focus movement.

**Architecture:** Keep navigation rules in the existing pure state types so they remain testable without SwiftUI. `SettingsFocus` owns its visible order and adjustment/command semantics; `VirtualKeyboardState` owns key geometry and chooses the nearest key center when moving between unequal rows.

**Tech Stack:** Swift 6, SwiftUI, TVShellChecks executable

**Status:** Completed and verified on 2026-07-11. The browser-injected keyboard was also synchronized with the native Da-Qian layout.

---

## Task 1: Lock down Settings focus behavior

- [ ] In `Sources/TVShellChecks/main.swift`, change `checkSettingsFocusIncludesVideoAndWebZoom()` to assert the visible order `scale → wallpaper → webZoom → videoSource → danmakuSize → danmakuSpeed → danmakuOpacity → danmakuDensity → credentials`.
- [ ] Assert `.scale.previous == .scale` and `.credentials.next == .credentials` so boundaries never wrap.
- [ ] Assert video source and credentials are command rows while display values are adjustable rows.
- [ ] Run `swift run TVShellChecks` and confirm the new Settings assertions fail.
- [ ] In `Sources/TVShellCore/Settings/SettingsFocus.swift`, implement the visible order, clamped `next`/`previous`, and `isAdjustable`.
- [ ] In `Sources/TVShellCore/App/AppState.swift`, let left/right change only adjustable settings and let OK/select activate command rows.
- [ ] Run `swift run TVShellChecks` and confirm Settings checks pass.

## Task 2: Lock down the Da-Qian Zhuyin layout

- [ ] In `Sources/TVShellChecks/main.swift`, assert the exact four Da-Qian character rows and the separate action row.
- [ ] Add a layout-switch assertion that switching layouts resets focus to the first key.
- [ ] Add navigation assertions showing vertical moves select the closest key center across unequal rows.
- [ ] Run `swift run TVShellChecks` and confirm the new keyboard assertions fail.
- [ ] In `Sources/TVShellCore/Input/VirtualKeyboardState.swift`, replace the current Zhuyin grouping with the standard Da-Qian rows.
- [ ] Give each key a logical navigation width matching `VirtualKeyboardView` and choose the closest destination center during up/down movement.
- [ ] Reset row, column, and candidate focus after a layout switch.
- [ ] Run `swift run TVShellChecks` and confirm the full suite passes.

## Task 3: Publish the completed stage

- [ ] Inspect `git diff` and confirm no unrelated user changes are included.
- [ ] Commit the implementation on `main` with a focused message.
- [ ] Push `main` to `origin`.
