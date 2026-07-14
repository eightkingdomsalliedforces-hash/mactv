# Windows and Android TV 1:1 Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the incomplete Compose shell aliases and external launches with the same typed routes, settings pages, anime services, history behavior, embedded browser, and internal player experience exposed by macOS TVShell.

**Architecture:** Common Kotlin reducers own every TVShell route and its D-pad behavior. Windows and Android adapters only provide persistence, credential import, embedded web/media surfaces, installed apps, and operating-system services; the main shell and standalone Anime app reuse the same anime service implementations.

**Tech Stack:** Kotlin Multiplatform, Compose Multiplatform, Android WebView/MediaPlayer, JavaFX WebView/Media on Windows, kotlinx.serialization, SwiftUI reference checks, Gradle/JUnit.

## Global Constraints

- macOS remains Swift and is the canonical visual and behavior reference.
- Windows and Android TV render from the same common Compose routes and reducers.
- CSS1 defaults to `https://sub.creamycake.org/v1/css1.json` and remains user-resettable.
- Official authentication, advertising, age, entitlement, and region controls are preserved.
- All visible product strings are Traditional Chinese and all scrollbars remain hidden.
- Every production behavior begins with a failing reducer/parser/adapter test.
- Commits go directly to `main` and are pushed to `origin`.

---

### Task 1: Typed built-in app routing

**Files:**
- Create: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/ShellNavigation.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellApp.kt`
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/LauncherStateTest.kt`

**Interfaces:**
- Produces: `ShellRoute`, `BuiltInAppRoute.routeFor(appID)`, and `ShellNavigationState.reduce(command)`.
- Consumes: `RemoteCommand` and launcher built-in app IDs.

- [ ] Add failing tests proving all ten built-ins map to distinct expected routes and Back/Home follow the macOS hierarchy.
- [ ] Run `./gradlew :shared-ui:desktopTest --tests dev.tvshell.shared.LauncherStateTest` and confirm failures mention missing route types.
- [ ] Implement the route reducer and replace `ShellScreen` launcher ID aliases.
- [ ] Add dedicated, fully rendered Remote Settings, Anime Source Management, and App Management split pages with distinct titles, content, actions, and Back behavior.
- [ ] Re-run the focused test and commit the green route slice.

### Task 2: CSS1, credentials, settings, and persistence contract

**Files:**
- Create: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/ShellPersistence.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/SettingsState.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/anime/CSS1Danmaku.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellContract.kt`
- Modify: platform adapters under `desktopMain`, `androidMain`, `android-app`, `anime-desktop`, and `anime-android-app`.
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/LauncherStateTest.kt`
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/CrossPlatformAnimeTest.kt`

**Interfaces:**
- Produces: `ShellPreferences`, `AnimeSourceSettings`, `PlatformAdapter.load/savePreferences`, `credentialsLocation`, and configurable `CSS1Resolver.subscriptionURL`.

- [ ] Add failing tests for the macOS CSS1 default, reset, invalid URL rejection, credentials path label, and persisted history/settings serialization.
- [ ] Run the focused tests and confirm they fail for missing configuration APIs.
- [ ] Implement common serializable state and atomic desktop/Android storage.
- [ ] Render CSS1 URL, state, health, reset/import actions, and credentials path in distinct settings pages.
- [ ] Re-run focused tests and commit the green configuration slice.

### Task 3: Compact deletable history and app management

**Files:**
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/NativeMedia.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellContract.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellApp.kt`
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/NativeMediaTest.kt`
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/LauncherStateTest.kt`

**Interfaces:**
- Produces: deterministic `WatchHistoryState.delete`, `clear`, launcher history actions, and `AppManagementState`.

- [ ] Add failing tests for delete-current, clear-all, focus repair, persistence callback, and installed-app refresh actions.
- [ ] Run focused tests and verify the expected behavior failures.
- [ ] Implement reducer actions and compact 340×116-equivalent history cards with a focusable Clear action.
- [ ] Implement the dedicated app-management split page and platform-safe management actions.
- [ ] Re-run tests and commit the green history/management slice.

### Task 4: Embedded browser and internal media runtime

**Files:**
- Create: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/PlatformWebSurface.kt`
- Create: `platforms/compose/shared-ui/src/androidMain/kotlin/dev/tvshell/shared/PlatformWebSurface.android.kt`
- Create: `platforms/compose/shared-ui/src/desktopMain/kotlin/dev/tvshell/shared/PlatformWebSurface.desktop.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/NativeMedia.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellApp.kt`
- Modify: `platforms/compose/shared-ui/build.gradle.kts`
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/NativeMediaTest.kt`

**Interfaces:**
- Produces: `WebRuntimeCommand`, `PlatformWebSurface`, Browser route state, and internal player command sequencing.

- [ ] Add failing tests proving Browser/YouTube/Bilibili/official sources stay inside TVShell and player commands do not invoke external launch actions.
- [ ] Run focused tests and confirm the external-launch behavior fails them.
- [ ] Implement Android WebView and Windows JavaFX WebView surfaces with hidden scrollbars and D-pad JavaScript controls.
- [ ] Render generic browser and player routes using the embedded surface; keep direct Android video on MediaPlayer.
- [ ] Re-run tests, compile Windows desktop plus Android, and commit the green runtime slice.

### Task 5: Share complete anime services with main shells

**Files:**
- Create: common platform anime service adapters under `shared-ui/src/*Main/kotlin/dev/tvshell/shared/anime/`.
- Modify: `platforms/compose/shared-ui/src/desktopMain/kotlin/dev/tvshell/desktop/Main.kt`
- Modify: `platforms/compose/android-app/src/main/kotlin/dev/tvshell/android/MainActivity.kt`
- Modify: standalone Anime entry points to reuse the same service adapters.
- Test: `platforms/compose/shared-ui/src/commonTest/kotlin/dev/tvshell/shared/CrossPlatformAnimeTest.kt`
- Test: `platforms/compose/shared-ui/src/desktopTest/kotlin/dev/tvshell/shared/anime/PlatformCSS1ContentClientTest.kt`

**Interfaces:**
- Produces: identical CSS1/Bilibili/YouTube/AniGamer/danmaku/player capabilities in full TVShell and standalone Anime.

- [ ] Add failing capability tests showing full-shell adapters must not fall back to `尚未設定 CSS1 訂閱網址` or external playback.
- [ ] Run the tests and confirm the main-shell capability gap.
- [ ] Extract and reuse the working CSS1/Dandanplay/Bilibili implementations, configured by persisted CSS1 URL and credentials.
- [ ] Keep official pages in embedded runtime and direct streams in internal player.
- [ ] Re-run CSS1 live smoke, parser tests, desktop tests, and Android compilation; commit the green anime slice.

### Task 6: Visual, focus, remote, and unreported-regression audit

**Files:**
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellApp.kt`
- Modify: `platforms/compose/shared-ui/src/commonMain/kotlin/dev/tvshell/shared/TVShellVisualSystem.kt`
- Modify: relevant common reducer tests.

**Interfaces:**
- Consumes: every route from Tasks 1–5.
- Produces: final macOS-equivalent focus order, split pages, card dimensions, auto-scroll, and hidden-scrollbar behavior.

- [ ] Add route reachability and every-command matrix tests covering all built-in pages, empty/loading/error states, and 720p/1080p token scaling.
- [ ] Run the matrix and record every unexpected failure before editing UI.
- [ ] Fix all discovered focus traps, wrong route titles, oversized cards, duplicate commands, non-scrolling focus, and visible scrollbars.
- [ ] Build local macOS Swift reference and Compose desktop, capture the same launcher/settings/anime states, and compare layout geometry.
- [ ] Run `swift build -c release --product TVShell && swift run TVShellChecks` plus the complete Gradle desktop/Android/package matrix.
- [ ] Commit and push `main`, monitor GitHub Build and Release, and verify refreshed macOS, Windows MSI/portable ZIP, and Android TV APK assets.
