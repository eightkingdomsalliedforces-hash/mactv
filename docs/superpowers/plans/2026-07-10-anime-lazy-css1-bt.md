# Anime Lazy CSS1 Resolution and BT Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the anime home screen load metadata promptly, defer CSS1 and BT resolution until a title is opened, and keep CSS1 as the preferred playable line.

**Architecture:** `AnimeHomeSourceProvider` will use a metadata provider for home and delegate title-specific episode discovery to a catalog provider. `CatalogAnimeSourceProvider` will resolve enabled adapters concurrently under a bounded deadline, merge their episode lines, and rank CSS1 candidates ahead of BT. The runtime will associate each async load with a generation so stale completion cannot retain the loading UI or overwrite newer results.

**Tech Stack:** Swift 6, SwiftUI, Foundation URLSession, Swift Package Manager, `TVShellChecks` executable checks.

## Global Constraints

- Keep CSS1 enabled and preferred when the user enabled it in the source catalog.
- Do not bypass Cloudflare, CAPTCHAs, DRM, login walls, or website protection.
- Do not make aria2c source-resolution deadlines terminate a torrent task after the viewer explicitly selected it.
- Every network request uses a bounded timeout and respects task cancellation.

---

## File structure

- `Sources/TVShellCore/Anime/DandanplayProvider.swift`: shared URLSession request timeout and cancellation behavior.
- `Sources/TVShellCore/Anime/CatalogAnimeSourceProvider.swift`: per-title concurrent adapter resolution, episode and playback-line merging, CSS1 priority.
- `Sources/TVShellCore/Anime/AnimeProviders.swift`: split metadata home search from deferred episode discovery.
- `Sources/TVShellCore/Anime/AnimeRuntimeView.swift`: generation-safe runtime loads and source catalog reloads.
- `Sources/TVShellChecks/main.swift`: deterministic regressions using static/delayed adapters.

### Task 1: Bound shared HTTP requests

**Files:**

- Modify: `Sources/TVShellCore/Anime/DandanplayProvider.swift:7-29`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**

- Produces: `URLSessionAnimeHTTPTransport.init(requestTimeout: TimeInterval = 8)`.
- Produces: `AnimeHTTPError.timedOut(String)` for user-visible source failures.

- [ ] **Step 1: Write the failing test**

Add a check that constructs the default transport and asserts its configured timeout is eight seconds:

```swift
let transport = URLSessionAnimeHTTPTransport()
try expect(transport.requestTimeout == 8, "anime requests use an eight-second timeout")
```

- [ ] **Step 2: Run the failing check**

Run: `swift run TVShellChecks`

Expected: build failure because `requestTimeout` does not exist.

- [ ] **Step 3: Write minimal implementation**

Expose `public let requestTimeout`, set `urlRequest.timeoutInterval`, and check cancellation before and after the URLSession call:

```swift
public let requestTimeout: TimeInterval

public init(requestTimeout: TimeInterval = 8) {
    self.requestTimeout = max(1, requestTimeout)
}

urlRequest.timeoutInterval = requestTimeout
try Task.checkCancellation()
let (data, response) = try await URLSession.shared.data(for: urlRequest)
try Task.checkCancellation()
```

- [ ] **Step 4: Run the check to verify it passes**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TVShellCore/Anime/DandanplayProvider.swift Sources/TVShellChecks/main.swift
git commit -m "fix: bound anime HTTP request timeouts"
```

### Task 2: Defer source episode discovery and preserve CSS1/BT lines

**Files:**

- Modify: `Sources/TVShellCore/Anime/CatalogAnimeSourceProvider.swift:29-94`
- Modify: `Sources/TVShellCore/Anime/AnimeProviders.swift:59-144`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**

- Produces: `CatalogAnimeSourceProvider.episodes(for:) async throws -> [AnimeEpisode]` that searches each enabled adapter using `AnimeSearchQuery(keyword: result.title)`.
- Produces: `CatalogAnimeSourceProvider.streams(for:) async throws -> [AnimeStreamCandidate]` sorted with CSS1 priority above BT.
- Consumes: `AnimeEpisode.identity.providerID`, `AnimeEpisode.playbackLines`, and adapter `search`, `episodes`, `streams` methods.

- [ ] **Step 1: Write the failing tests**

Create static CSS1 and BT adapters that only return results after the title query, then assert both sources contribute lines and CSS1 is first:

```swift
let episodes = try await provider.episodes(for: AnimeSearchResult(id: "home", title: "測試動畫", episodes: []))
try expect(episodes.map(\.number) == [1], "deferred sources merge one episode by number")
let streams = try await provider.streams(for: episodes[0])
try expect(streams.map { $0.headers["resolver"] } == ["web-selector", "torrent"], "CSS1 is preferred before BT fallback")
```

Also assert `AnimeHomeSourceProvider.search(AnimeSearchQuery(keyword: ""))` only calls its metadata provider and does not invoke those adapters.

- [ ] **Step 2: Run the failing check**

Run: `swift run TVShellChecks`

Expected: the deferred-source assertions fail because catalog episodes currently return the home result's embedded episodes and source lines are not merged.

- [ ] **Step 3: Write minimal implementation**

Add an adapter-resolution helper that searches the selected title, selects same-title candidates, asks each matching adapter for episodes, and merges them by number. Preserve every candidate as `AnimeEpisodePlaybackLine` with a provider-qualified line id. In `streams(for:)`, resolve all stored lines and sort with:

```swift
func priority(for stream: AnimeStreamCandidate) -> Int {
    switch stream.headers["resolver"] {
    case "web-selector": return 300
    case "torrent": return 100
    default: return 200
    }
}
```

Update `AnimeHomeSourceProvider.episodes(for:)` to delegate to `base.episodes(for:)`, so initial home cards can contain no eagerly-resolved episodes.

- [ ] **Step 4: Run the check to verify it passes**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TVShellCore/Anime/CatalogAnimeSourceProvider.swift Sources/TVShellCore/Anime/AnimeProviders.swift Sources/TVShellChecks/main.swift
git commit -m "feat: defer CSS1 and BT episode resolution"
```

### Task 3: Isolate slow or failed CSS1 sources

**Files:**

- Modify: `Sources/TVShellCore/Anime/CatalogAnimeSourceProvider.swift:57-86`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**

- Produces: `CatalogAnimeSourceProvider.resolveEpisodes(for:) async -> [AnimeEpisode]` with an eight-second source deadline.
- Consumes: enabled `AnimeMediaSourceAdapter` values.

- [ ] **Step 1: Write the failing test**

Add a delayed CSS1 adapter that sleeps past a short injected test deadline and a healthy adapter that returns episode one. Assert the returned list contains the healthy episode and the completion time remains below the delayed source duration:

```swift
let started = ContinuousClock.now
let episodes = try await provider.episodes(for: title)
try expect(episodes.count == 1, "healthy source survives CSS1 timeout")
try expect(started.duration(to: .now) < .seconds(1), "timeout does not block episode screen")
```

- [ ] **Step 2: Run the failing check**

Run: `swift run TVShellChecks`

Expected: the check waits for the delayed adapter or exceeds the duration assertion because adapters resolve serially.

- [ ] **Step 3: Write minimal implementation**

Run enabled adapter searches in a throwing task group that converts each individual error and deadline into an empty result. Inject `sourceResolutionTimeoutNanoseconds` through the catalog provider initializer for deterministic checks. Race each adapter resolution against `Task.sleep`; after the first result, cancel the losing task and return without awaiting an uncooperative source task. Never call this helper from `TorrentPlaybackEngine.startStreaming`.

- [ ] **Step 4: Run the check to verify it passes**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TVShellCore/Anime/CatalogAnimeSourceProvider.swift Sources/TVShellChecks/main.swift
git commit -m "fix: isolate stalled CSS1 source resolution"
```

### Task 4: Make runtime loads generation-safe and reload catalog changes

**Files:**

- Modify: `Sources/TVShellCore/Anime/AnimeRuntimeView.swift:75-118,441-560`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**

- Produces: `AnimeRuntimeController.loadGeneration: UInt` and a cancellable `loadTask`.
- Consumes: `AppState.animeSourceCatalog` through a SwiftUI `.onChange` reload trigger.

- [ ] **Step 1: Write the failing test**

Use a controller with a delayed first provider and an immediate second provider. Start both loads in order, then assert the final `statusText` and titles come from the second provider:

```swift
await controller.load(sourceProvider: slowProvider)
await controller.load(sourceProvider: fastProvider)
try expect(controller.titles.first?.title == "快速結果", "stale load cannot replace current titles")
```

Add a source-catalog mutation assertion that changing `isEnabled` triggers `reloadConfiguredSources()` from the view.

- [ ] **Step 2: Run the failing check**

Run: `swift run TVShellChecks`

Expected: stale results can win or the view source does not observe `animeSourceCatalog`.

- [ ] **Step 3: Write minimal implementation**

Increment a generation before every load, cancel the previous load task, and apply title/status changes only if the captured generation remains current. In the view add:

```swift
.onChange(of: appState.animeSourceCatalog) { _, _ in
    reloadConfiguredSources()
}
```

When reloading, set `statusText` to `正在更新動漫來源...` before awaiting the new provider so the UI never carries a stale loading message.

- [ ] **Step 4: Run the check to verify it passes**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/TVShellCore/Anime/AnimeRuntimeView.swift Sources/TVShellChecks/main.swift
git commit -m "fix: refresh anime sources without stale loads"
```

### Task 5: Verify the integrated behavior

**Files:**

- Modify: `README.md` only if user-visible source behavior changes require clarification.

- [ ] **Step 1: Run the targeted checks**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed`.

- [ ] **Step 2: Build the application**

Run: `swift build -c release --product TVShell`

Expected: `Build complete!` with exit status 0.

- [ ] **Step 3: Inspect final changes**

Run: `git diff main...HEAD --check && git status --short`

Expected: no whitespace errors and no uncommitted files.

- [ ] **Step 4: Commit any documentation change**

```bash
git add README.md
git commit -m "docs: explain deferred anime source loading"
```

Only run this commit when `README.md` changed.
