# ShowRunner Implementation Roadmap

This roadmap tracks the next implementation pass after the initial YouTube, Moderation Docker, overlay URL, and node editor MVP work.

## Working Rules

- Work stays on feature branches until explicitly merged.
- Use separate semantic commits for each completed feature or fix.
- Keep upstream CastMate package names where they are technical module identifiers.
- Prefer additive changes over broad rewrites while the fork is still close to upstream.
- Run `corepack yarn check` after each meaningful batch.

## Priority 1: Node Editor V2

1. Done: Add canvas zoom controls.
2. Done: Add canvas pan with middle mouse.
3. Done: Add fit-to-content and reset-view buttons.
4. Done: Add search/filter for the node action palette.
5. Done: Allow dropping a new action directly onto the canvas.
6. Done: Allow inserting an action between two connected nodes.
7. Done: Show explicit connection handles on action nodes.
8. Done: Add keyboard shortcuts for delete, duplicate, and fit view.
9. Done: Add undo-friendly mutations for node editor operations.
10. Done: Persist node editor view state per automation.

## Priority 2: Automation Timeline / DAW Feel

11. Done: Add a running playhead preview for automation execution.
12. Done: Show action durations and offsets more clearly in node mode.
13. Done: Add snap-to-grid controls for node movement.
14. Done: Add action grouping lanes for time, flow, and floating sequences.
15. Done: Add a compact node activity log beside the editor.

## Priority 3: Integrations

16. Done: Add a YouTube connection checklist with clearer OAuth state.
17. Done: Add YouTube live chat auto-start option after successful login.
18. Done: Add YouTube quota/error hints in the integration page.
19. Done: Add Twitch account status card under Integrations.
20. Done: Add Moderation Docker connection presets for local and Docker host networking.
21. Done: Add Moderation Docker latest decision feed in the integration page.

## Priority 4: Overlay Studio

22. Done: Add overlay browser source copy/open controls to the overlay list.
23. Done: Add preview frame sizing presets for common OBS canvases.
24. Done: Add quick label templates for YouTube/Twitch state.
25. Done: Add a visible save/live preview status indicator.
26. Done: Add shader-capable scene overlay planning in docs before implementation.

## Priority 5: UI Cleanup

27. Done: Make the Integrations group the obvious home for Twitch, YouTube, OBS, and Moderation.
28. Reduce duplicated top-level entries where integration settings are hidden.
29. Done: Replace ambiguous icon-only buttons with tooltips where missing.
30. Done: Document the new first-run setup path and local test commands.

## Current Batch

Continue with navigation deduplication, scene overlay resource implementation, shader editor MVP, richer automation preview timing, and live overlay websocket presence.
