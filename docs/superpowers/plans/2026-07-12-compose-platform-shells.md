# Compose Platform Shells Implementation Plan

**Goal:** Create buildable Android TV and Windows TVShell applications that share one Compose UI and the macOS tvOS 18 visual/focus contract.

## Tasks

1. Add language-neutral 1080p design, remote-command, launcher-app, and anime contracts. Verify Swift and Kotlin constants against the same fixtures.
2. Create a Compose Multiplatform `shared-ui` module with the rectangular launcher dock, backdrop, status area, focus reducer, automatic focused-item scrolling, settings/control-center shells, and Anime product route.
3. Create an Android TV app with `play` and `launcher` product flavors. Both declare `LEANBACK_LAUNCHER`; only `launcher` declares `HOME` and `DEFAULT`. Add TV app discovery, separate-process launch, package-change refresh, Android settings escape route, and D-pad mapping.
4. Create a Windows Compose Desktop entry point using the same `shared-ui`, Start Menu discovery, separate-process launch adapter, fullscreen support, and Windows packaging configuration.
5. Add common reducer/contract tests, Android manifest tests, and build checks. Document exact build artifacts and SDK requirements.
6. Run all locally available checks, commit coherent slices, and push `main`.

Versions are pinned to an officially documented compatible toolchain and updated only after the builds pass.
