# ShowRunner Implementation Roadmap

This roadmap tracks the next implementation pass after the initial YouTube, Moderation Docker, overlay URL, and node editor MVP work.

## Working Rules

- Work stays on feature branches until explicitly merged.
- Use separate semantic commits for each completed feature or fix.
- Keep upstream CastMate package names where they are technical module identifiers.
- Prefer additive changes over broad rewrites while the fork is still close to upstream.
- Run `corepack yarn check` after each meaningful batch.

## Priority 1: Node Editor V2

1. Add canvas zoom controls.
2. Add canvas pan with middle mouse or space-drag.
3. Add a minimap or fit-to-content button.
4. Add search/filter for the node action palette.
5. Allow dropping a new action directly onto the canvas.
6. Allow inserting an action between two connected nodes.
7. Show explicit connection handles on action nodes.
8. Add keyboard shortcuts for delete, duplicate, and fit view.
9. Add undo-friendly mutations for node editor operations.
10. Persist node editor view state per automation.

## Priority 2: Automation Timeline / DAW Feel

11. Add a running playhead preview for automation execution.
12. Show action durations and offsets more clearly in node mode.
13. Add snap-to-grid controls for node movement.
14. Add action grouping lanes for time, flow, and floating sequences.
15. Add a compact execution log beside the editor.

## Priority 3: Integrations

16. Add a YouTube connection checklist with clearer OAuth state.
17. Add YouTube live chat auto-start option after successful login.
18. Add YouTube quota/error hints in the integration page.
19. Add Twitch account status card under Integrations.
20. Add Moderation Docker connection presets for local and Docker host networking.
21. Add Moderation Docker latest decision feed in the integration page.

## Priority 4: Overlay Studio

22. Add overlay browser source copy/open controls to the overlay list.
23. Add preview frame sizing presets for common OBS canvases.
24. Add quick label templates for YouTube/Twitch state.
25. Add a visible save/live preview status indicator.
26. Add shader-capable scene overlay planning in docs before implementation.

## Priority 5: UI Cleanup

27. Make the Integrations group the obvious home for Twitch, YouTube, OBS, and Moderation.
28. Reduce duplicated top-level entries where integration settings are hidden.
29. Replace ambiguous icon-only buttons with tooltips where missing.
30. Document the new first-run setup path and local test commands.

## Current Batch

Start with Node Editor V2 because it is the biggest usability gap compared with CastMate's strongest workflow.
