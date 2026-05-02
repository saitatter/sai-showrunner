# ShowRunner Implementation Roadmap

This roadmap tracks the next implementation pass after the initial YouTube, Moderation Docker, overlay URL, and node editor MVP work.

## Working Rules

- Work stays on feature branches until explicitly merged.
- Use separate semantic commits for each completed feature or fix.
- Keep upstream ShowRunner package names where they are technical module identifiers.
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
10a. Done: Extract node canvas, drag, context menu, and preview behavior into focused composables.

## Priority 2: Automation Timeline / DAW Feel

11. Done: Add a running playhead preview for automation execution.
11a. Done: Add progress, elapsed time, and duration-aware pacing to the node preview playhead.
12. Done: Show action durations and offsets more clearly in node mode.
13. Done: Add snap-to-grid controls for node movement.
14. Done: Add action grouping lanes for time, flow, and floating sequences.
15. Done: Add a compact node activity log beside the editor.

## Priority 3: Integrations

16. Done: Add a YouTube connection checklist with clearer OAuth state.
17. Done: Add YouTube live chat auto-start option after successful login.
18. Done: Add YouTube quota/error hints in the integration page.
18a. Done: Add YouTube API diagnostics with search cooldown, estimated quota, last API error, and retry state.
19. Done: Add Twitch account status card under Integrations.
20. Done: Add Moderation Docker connection presets for local and Docker host networking.
21. Done: Add Moderation Docker latest decision feed in the integration page.
22. Done: Add decision-only moderation action for Twitch/YouTube chat automations.
23. Done: Add native Moderation Docker queue page with override actions.

## Priority 4: Overlay Studio

24. Done: Add overlay browser source copy/open controls to the overlay list.
25. Done: Add preview frame sizing presets for common OBS canvases.
26. Done: Add quick label templates for YouTube/Twitch state.
27. Done: Add a visible save/live preview status indicator.
27a. Done: Back the live preview indicator with real overlay websocket subscriber presence.
28. Done: Add shader-capable scene overlay planning in docs before implementation.
29. Done: Add native Chat Feed widget for approved chat messages.
30. Done: Add automation action that pushes approved messages to Chat Feed.
30a. Done: Allow chat push actions to target a specific Chat Feed widget.
31. Done: Add bundled WebGL Shader Layer widget.
31a. Done: Add a local custom fragment shader editor mode for Shader Layer.
31b. Done: Add local Shader Layer preset save/load for custom fragment sources.
31c. Done: Add richer bundled shader presets with visual preset cards and custom-source validation hints.
31d. Done: Add Paid Alert widget and `Push Paid Alert` automation action.
31e. Done: Add Scene Banner widget and begin/end scene overlay automation actions.

## Priority 5: UI Cleanup

32. Done: Make the Integrations group the obvious home for Twitch, YouTube, OBS, and Moderation.
33. Verified: Twitch, YouTube, OBS, and Moderation are already grouped under Integrations; avoid risky nav moves until the next wider sidebar cleanup.
34. Done: Replace ambiguous icon-only buttons with tooltips where missing.
35. Done: Document the new first-run setup path and local test commands.
36. Done: Document moderation/chat overlay migration path.

## Current Batch

Current batch complete:

1. Done: Add automation templates for Twitch/YouTube chat -> moderation filter -> targeted Chat Feed.
2. Done: Add overlay runtime websocket presence to the widget list, not only the editor header.
3. Done: Add local Shader Layer preset save/load once the local editor UX is stable.
4. Done: Add moderation queue filters/search and richer override audit details.
5. Done: Extract node preview timing into `useAutomationPreview`.
6. Done: Extract node canvas, drag, and context menu behavior into composables.
7. Done: Add richer shader preset workflow, YouTube API diagnostics, paid alerts, and scene banner events.

Next batch:

1. Build a common context menu surface shared by Nodes and Timeline.
2. Add node type styling improvements for triggers, actions, paid alerts, moderation filters, and overlay actions.
3. Add automation templates for YouTube paid alert -> Paid Alert widget and scene begin/end flows.
4. Add richer manual YouTube discovery controls for stream IDs/live chat IDs.
5. Add deeper OBS preview validation for Chat Feed, Paid Alert, Scene Banner, and Shader Layer widgets.
