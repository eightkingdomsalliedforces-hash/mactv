# tvOS UI Reference for TVShell

## Sources Reviewed

- Apple Human Interface Guidelines: Designing for tvOS
- Apple Human Interface Guidelines: Focus and selection
- Apple Human Interface Guidelines: Remotes
- Apple Developer: Support directional remotes in your tvOS app
- Apple Developer WWDC25: Meet Liquid Glass
- Apple Newsroom: tvOS 26 Liquid Glass redesign
- Apple Support: Apple TV 4K User Guide for tvOS 26

## Core Direction

TVShell should look and behave like a content-first Apple TV interface, not a desktop launcher enlarged for a television.

The UI must prioritize:

- Large, cinematic content surfaces.
- Remote-first directional navigation.
- A visible focused item at all times.
- Subtle depth, parallax, lift, and focus expansion.
- Liquid Glass as a floating control material, not as decoration everywhere.
- Minimal chrome while media is playing.
- Poster/app artwork as the primary visual language.

## Layout

The launcher should evolve from a simple icon row into a tvOS-style home screen:

- A hero area at the top or background layer for the focused app/content.
- Horizontal rows for apps, recent items, media, web apps, and settings.
- Large cards/posters with generous spacing.
- Minimal persistent navigation.
- Contextual control surfaces that appear only when needed.

Recommended structure:

```text
Background:
  focused app/content artwork, blurred/tinted, full-bleed

Top:
  subtle profile/status/time/control center row

Main:
  hero title or selected app name
  primary action hints

Rows:
  Continue / Recent
  Apps
  Media
  Tools / Settings

Overlay:
  Liquid Glass control panel only when focused/needed
```

## Focus Behavior

Focus is the soul of tvOS. Every focusable element should:

- Scale up.
- Lift slightly.
- Gain a bright but soft edge highlight.
- Cast a larger shadow/glow.
- Trigger a background/artwork response.
- Animate with spring-like motion.

The focused card should feel selected from across the room. Non-focused cards should remain readable but visually quieter.

Directional movement must remain predictable:

- Left/Right moves through rows.
- Up/Down moves between rows.
- Back exits overlays or returns one level.
- Home returns to launcher.
- Menu opens context actions.

## Liquid Glass

Use Liquid Glass for floating controls and focused surfaces:

- Control Center panels.
- Focused app cards.
- Media controls.
- Permission/status panels.
- Settings selectors.

Avoid making every page a glass panel. The material should support content, not bury the screen in frosted rectangles.

Visual traits:

- Translucent material.
- Refraction-like bright edge.
- Specular highlight.
- Subtle color from the background.
- Rounded, floating shape.
- Depth and motion on focus.

## Media Runtime

While video is playing:

- Video remains visually dominant.
- Controls float above content in Liquid Glass.
- Playback controls should be large and sparse.
- Seek feedback should not cover the center of the image for long.
- Back first hides controls or exits media, depending on current control state.
- Home always returns to the launcher.

## Settings and App Management

Settings should feel like Apple TV settings:

- Big rows.
- Clear focused row.
- Large value selector on the right.
- Minimal explanatory text.
- Remote-first controls.

App management should use a grid/list hybrid:

- App card grid for arrangement.
- Large inspector panel for selected app details.
- Remote-friendly actions: Move, Hide, Edit, Delete, Control Mode, Scale.

## Implementation Changes to Make Next

1. Replace the current single launcher row with multiple tvOS-style horizontal rows.
2. Add focused-background artwork/tint that changes as focus moves.
3. Make AppCard support poster and icon modes.
4. Add row title typography and larger vertical rhythm.
5. Add a tvOS-like Control Center overlay.
6. Replace settings layout with large focused rows.
7. Convert media controls into a Liquid Glass floating transport bar.
8. Add focus parallax using small pointer/remote movement or synthetic focus offset.
9. Add reduce-motion and increase-contrast options.

## Design Rules

- Remote behavior is more important than visual flourish.
- The focused item must be obvious at 10 feet.
- Avoid desktop UI patterns: tiny sidebars, dense forms, toolbar buttons, and window-like panels.
- Prefer artwork, rows, and overlays.
- Use Liquid Glass sparingly, with intent.
- Keep video/content front and center.
