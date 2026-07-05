# Wallpaper Phase 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a remote-friendly wallpaper system with built-in cinematic presets and a provider abstraction for future local-folder, URL-feed, or third-party wallpaper sources.

**Architecture:** Add pure wallpaper models covered by `TVShellChecks`, store the selected wallpaper in `AppState`, extend Settings navigation with scale and wallpaper rows, and make the launcher hero background render from the selected wallpaper.

**Tech Stack:** Swift Package Manager, SwiftUI, `TVShellChecks`.

---

## Tasks

1. Add failing checks for wallpaper preset cycling and static provider output.
2. Implement `WallpaperSource`, `WallpaperPreset`, `WallpaperPalette`, and `StaticWallpaperProvider`.
3. Add `SettingsFocus` so remote Up/Down chooses between UI Scale and Wallpaper.
4. Update Settings Left/Right/OK to change the focused setting.
5. Render the selected wallpaper in the launcher background.
6. Verify with checks, release build, and short launch.
