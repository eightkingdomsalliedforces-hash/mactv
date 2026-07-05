# Media and Big Screen Scale Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real media runtime with remote playback commands and a TV-scale setting screen so the shell is more usable on 1080p, 2K, 4K, and larger displays.

**Architecture:** Add pure core types for media command reduction and display scale, cover them in `TVShellChecks`, then wire them into SwiftUI/AppKit runtime views. Keep remote command dispatch centralized in `AppState`, and keep media playback commands flowing through the existing runtime notification channel.

**Tech Stack:** Swift Package Manager, SwiftUI, AVKit/AVFoundation, AppKit, `TVShellChecks`.

---

## Tasks

1. Add failing checks for `MediaControlState` and `DisplayScale`.
2. Implement `DisplayScale` with Auto, 100%, 125%, 150%, and 200% options.
3. Implement `MediaControlState` command reducer for play/pause, seek, Home, and Back semantics.
4. Extend app routing with `.media` and `.settings` runtimes.
5. Add `MediaRuntimeView` backed by `AVPlayer`, controlled by remote notifications.
6. Add `SettingsView` where Left/Right changes UI scale and Home returns to launcher.
7. Apply UI scale to launcher cards and shell surfaces.
8. Verify with `swift run TVShellChecks`, `swift build --product TVShell`, `swift build -c release --product TVShell`, and a short launch smoke test.

## Acceptance

- Media command reducer toggles playback and seeks deterministically in checks.
- Display scale cycles through supported values in checks.
- Launcher includes a Media app and Settings app.
- Media runtime responds to Play/Pause, Left/Right, Rewind/FastForward, Back, and Home.
- Settings screen can change UI scale using remote Left/Right.
- Existing remote command mappings and Liquid Glass shell still build cleanly.
