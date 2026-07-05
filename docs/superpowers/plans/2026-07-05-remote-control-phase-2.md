# Remote Control Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the remote-first shell with local/global media-key capture, Android TV-style HID consumer mappings, and a first Liquid Glass visual layer for focused launcher cards.

**Architecture:** Extend the existing `TVShellCore` input path so keyboard, media-key, global monitor, and HID-like events still normalize into `RemoteCommand`. Keep UI code isolated from raw key codes, and apply Liquid Glass styling through reusable SwiftUI view modifiers instead of scattering visual constants through launcher code.

**Tech Stack:** Swift Package Manager, SwiftUI, AppKit `NSEvent` local/global monitors, HID consumer usage mapping, `TVShellChecks`.

---

## Tasks

1. Extend `KeyCodeMapper` media and HID mappings for Android TV-style Back/Home/Menu/OK and media transport keys.
2. Add AppKit media-key extraction and global event monitoring to `InputRouter`.
3. Add automated `TVShellChecks` coverage for the new mappings.
4. Add a `LiquidGlassCardModifier` and apply it to launcher cards and permission panels.
5. Run `swift run TVShellChecks`, `swift build --product TVShell`, and `swift build -c release --product TVShell`.

## Acceptance

- D-pad keyboard mappings still pass.
- Consumer HID usages for Home, Back, Play/Pause, Volume, Fast Forward, and Rewind map to `RemoteCommand`.
- Local `systemDefined` media key events can become `RemoteCommand.media`.
- A global event monitor is installed while the shell view is alive.
- Focused app cards use translucent layered material, soft highlight, and focus glow as the first Liquid Glass pass.
