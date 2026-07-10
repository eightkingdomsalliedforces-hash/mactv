# Animeko Compatibility Roadmap

MacTV adopts Animeko-compatible source subscriptions while preserving a macOS,
remote-first TV interface. The implementation is split into dependency-ordered
milestones so each feature remains testable on macOS.

## Implemented Foundation

- Bangumi metadata, covers, episode details, and watch history.
- Dandanplay comments with remote-friendly display controls.
- CSS1 and BT1 subscription ingestion, Mikan, DMHY, Jellyfin, and Emby adapters.
- AVFoundation and embedded VLC playback routing.
- BT cache inspection, resume, deletion, and physical-byte progress reporting.
- Large-screen focus navigation, virtual keyboard, and tvOS-style settings.

## Active Milestone: Playback Lines

1. Preserve every source line for an episode instead of flattening duplicate
   episode cards.
2. Present a remote-navigable line picker with source, quality, and health.
3. Persist the chosen line per work and episode.
4. Fall back to the next healthy line when playback resolution or player setup
   fails.

## Follow-up Milestones

- Replace the process-based BT bridge with a maintained embedded torrent backend
  where packaging and licensing permit it.
- Add task-level BT peer, tracker, piece, speed, ETA, and error state.
- Add Bangumi authenticated collection synchronization and an offline library.
- Add source health telemetry, subscription refresh, and explicit recovery
  controls without bypassing website protection or access restrictions.
