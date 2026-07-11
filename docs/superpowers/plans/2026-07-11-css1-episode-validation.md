# CSS1 Episode Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove CSS1 metadata cards and years from the episode grid without losing valid multi-source playback lines.

**Architecture:** Pass whether anchors came from the configured episode-list block into the selector validator. Combine structural context, playback URL shape and metadata-title rejection instead of accepting every title containing a number.

**Tech Stack:** Swift, CSS1HTMLSelectorEngine, TVShellChecks.

## Global Constraints

- Work directly on `main`.
- Do not use subagents.
- Preserve multi-source quality merging and Dandanplay fixes.
- Commit and push to `origin/main`.

---

### Task 1: Reject metadata cards from CSS1 episodes

**Files:**
- Modify: `Sources/TVShellChecks/main.swift`
- Modify: `Sources/TVShellCore/Anime/AniSubsCSS1SubscriptionProvider.swift`

**Interfaces:**
- Consumes: `parseEpisodes`, `CSS1HTMLSelectorEngine.isEpisodeAnchor`.
- Produces: context-aware CSS1 episode validation.

- [ ] **Step 1: Add the failing regression**

Extend a CSS1 detail fixture with valid `第 1 話` plus anchors titled `第13集 豆瓣:8.0分`, `更新至第25集 豆瓣評分` and `2021`. Assert the parsed episode numbers equal `[1]`.

- [ ] **Step 2: Confirm RED**

Run `swift run TVShellChecks`. Expect failure showing extra episode numbers 13, 25 and 2021.

- [ ] **Step 3: Implement strict validation**

Pass `isWithinEpisodeList` to `isEpisodeAnchor`. Reject metadata terms and year-only titles, remove `detail` from playback path recognition, and require either episode-list context or a playback URL for numbered titles.

- [ ] **Step 4: Verify and publish**

Run `git diff --check && swift run TVShellChecks`. Commit with `fix: filter CSS1 metadata from episodes`, push `origin main`, and verify local and remote are synchronized.

