# CSS1 Search Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent CSS1 episode loading time from growing linearly with the number of enabled web-selector sites and matching detail pages.

**Architecture:** Keep `AniSubsCSS1SubscriptionProvider` as the public adapter and introduce private per-source resolution values. Resolve independent sources concurrently, resolve up to six matching detail pages per source concurrently, then merge results and persist source health sequentially.

**Tech Stack:** Swift concurrency task groups, Swift Package Manager, existing `TVShellChecks` executable.

## Global Constraints

- Work directly on `main`.
- Do not use subagents.
- Preserve CSS1 failure descriptions and automatic skipping of failed sites.
- Push every completed commit to `origin/main`.

---

### Task 1: Prove independent CSS1 sites search concurrently

**Files:**
- Modify: `Sources/TVShellChecks/main.swift`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Consumes: `AniSubsCSS1SubscriptionProvider.search(_:)` and `DelayedAnimeHTTPTransport`.
- Produces: A timing regression that requires two delayed CSS1 source searches to overlap.

- [ ] **Step 1: Write the failing timing regression**

Add two web-selector sources whose search URLs each delay 150ms, provide one valid detail result per source, measure `provider.search`, assert both results are returned, and assert elapsed time is less than 260ms.

- [ ] **Step 2: Run the check and confirm RED**

Run: `swift run TVShellChecks`

Expected: failure stating CSS1 source searches should run concurrently, because the serial implementation takes about 300ms.

### Task 2: Parallelize source and detail resolution

**Files:**
- Modify: `Sources/TVShellCore/Anime/AniSubsCSS1SubscriptionProvider.swift`
- Test: `Sources/TVShellChecks/main.swift`

**Interfaces:**
- Consumes: `[AniSubsCSS1Source]`, `CSS1HTMLSelectorEngine.Anchor`, `html(for:source:)`, `parseEpisodes`.
- Produces: private `CSS1SourceSearchResolution` values containing source index, source name, results, failure reasons and health outcome.

- [ ] **Step 1: Add per-source resolution**

Move one source's existing search-page and detail-page work into a private async method. Return values instead of mutating shared arrays or writing the health store.

- [ ] **Step 2: Bound and parallelize detail requests**

Filter the subjects first, keep `prefix(6)`, and use a task group to resolve their detail pages concurrently. Sort completed values by original subject index before returning results.

- [ ] **Step 3: Parallelize independent CSS1 sources**

Use a task group in `search(_:)` to resolve all active sources concurrently. Sort resolutions by source index, flatten results and failure reasons, then call `recordSuccess` or `recordFailure` sequentially.

- [ ] **Step 4: Run GREEN verification**

Run: `swift run TVShellChecks`

Expected: `TVShellChecks passed` and the new timing assertion passes.

- [ ] **Step 5: Verify, commit and publish**

Run: `git diff --check && swift run TVShellChecks`

Then commit with `perf: parallelize CSS1 source searches` and run `git push origin main`.

