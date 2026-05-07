# ShowRunner v1.0 — Graph-Only Engine (Breaking Change)

Completely remove `SequenceRunner` and the old sequence model. All automations run exclusively through `GraphCompiler` → `GraphVM`.

---

## Phase 1: Remove Old Sequencer (Core)

### 1.1 Relocate shared types
- [x] Move debugger/runtime interfaces out of the old sequence runner path.
- [x] Move `SequenceResolvers` (rename to `ActionResolvers`) → `libs/showrunner-core/src/queue-system/resolvers.ts`
- [x] Add `ExecutionContext`, `AutomationSource`, `QueuedAutomation`, and `AutomationProvider` schema names.
- [x] Update queue/runtime imports to the new names.

### 1.2 Delete old runner
- [x] Delete `libs/showrunner-core/src/queue-system/sequence.ts` (SequenceRunner class)
- [x] Delete `libs/showrunner-core/src/queue-system/__tests__/sequence.test.ts`
- [x] Remove `SequenceRunner` export from `libs/showrunner-core/src/index.ts`

### 1.3 Simplify action-queue.ts
- [x] Remove dual-path: `runNext()`, `queueOrRun()`, `runTestSequence()` use only GraphVM
- [x] Remove `private runner: SequenceRunner | null` field
- [x] Remove `private testSequences = new Map<string, SequenceRunner>()`
- [x] Require `automation.graph`; missing graph is reported and recorded in queue history instead of silently dropping the item.
- [x] Add queue worker timeout and abort propagation to GraphVM/action `AbortSignal`.

### 1.4 Delete migration bridge
- [ ] Delete `libs/showrunner-core/src/graph-engine/migration.ts`
- [ ] Delete `libs/showrunner-core/src/graph-engine/__tests__/migration.test.ts`
- [ ] Remove exports from `libs/showrunner-core/src/graph-engine/index.ts`

---

## Phase 2: Schema Cleanup

### 2.1 Remove old sequence types
- [x] Remove from `libs/showrunner-schema/src/types/sequence.ts`:
  - `Sequence`, `FloatingSequence`, `ActionStack`, `TimeAction`, `FlowAction`, `InstantAction`
  - `OffsetActions`, `TimeActionInfo`, `SubFlow`
  - `isActionStack()`, `isFlowAction()`, `isTimeAction()`, `isInstantAction()`
  - `getActionById()`, `getActionAndPathById()`, `assignNewIds()`, `getSequenceResultVariables()`, `getActionResultVariables()`
- [x] Keep compatibility aliases while exposing primary graph/runtime names: `ActionInfo`, `ExecutionContext`, `AutomationSource`, `QueuedAutomation`, `AutomationProvider`

### 2.2 Simplify AutomationData
- [x] Remove `sequence: Sequence` field — `graph: AutomationGraph` becomes mandatory
- [x] Remove `floatingSequences: FloatingSequence[]` — subgraphs replace this
- [x] Update `createInlineAutomation()` to return empty graph: `{ graph: { nodes: [], edges: [], entryNodeId: "" }, subgraphs: [] }`
- [x] Remove `findActionById()`, `findActionAndSequenceById()`, `getActionByParsedPath()` traversal helpers

### 2.3 Update queues.ts
- [x] Replace `QueuedSequence` → `QueuedAutomation` in `ActionQueueState`
- [x] Update `ActionQueueConfig` types, including graph worker timeout.

---

## Phase 3: UI Cleanup (NodeAutomationEdit.vue)

### 3.1 Remove legacy rendering path
- [x] Remove `isActionStack`, `isFlowAction`, `isTimeAction` imports & usage from `NodeAutomationEdit`/node rendering.
- [x] Remove `addSequence()` function and all `Sequence | FloatingSequence` processing from the node editor.
- [x] Remove old node-building code that iterates `ActionStack`, `TimeAction`, etc.
- [x] Remove `addFloatingSequence()`, `deleteFloatingSequence()`, `runFloatingSequence()`
- [ ] Remove `cloneActionForNodeEditor()` (old sequence cloning logic)

### 3.2 Graph-only buildGraph()
- [x] `buildGraph()` always uses `buildGraphFromAutomationGraph()`
- [x] Remove fallback path that builds nodes from `automation.sequence`
- [x] Simplify `edges` computed — no conditional branch

### 3.3 Cleanup other UI files
- [ ] `ActionConfigEdit.vue` — remove `SubFlow` import if unused
- [x] `TimeActionEdit.vue` — remove or convert to graph-native time/delay node editor
- [x] `OffsetSequenceEdit.vue` — likely removable entirely (offsets not in graph model)
- [x] `automation-dragdrop.ts` — rewrite for graph nodes (no more `FloatingSequence`)

### 3.4 Simplification Batch Status
- [x] Profile triggers open directly in the node graph editor.
- [x] Legacy `AutomationEdit.vue`, sequence drop zones, time offset editors, and sequence mini preview were removed.
- [x] Inline automation previews now summarize graph data instead of reading `automation.sequence`.
- [x] Shader graph and node graph share the same themed collapsible context menu shell.
- [x] Renderer save/error feedback is routed through `useAppFeedback()` for toast + dev-only logging.
- [x] Reduced safe `@ts-expect-error` usage in resource registration and array wrappers.
- [x] Continue shrinking remaining console noise in media/viewer-data/satellite/drag utilities.
- [x] Rename queue terminology from `QueuedSequence` to `QueuedAutomation` in queue runtime/state.
- [x] Add one-time persistence migration to strip stale `sequence`/`floatingSequences` fields from existing user JSON.

---

## Phase 4: Data Migration (one-time, on load)

### 4.1 Upgrade migration in old-migration.ts
- [ ] Keep existing `old-migration.ts` for pre-v1.0 data → graph conversion
- [x] On app startup: auto-migrate any `automation.sequence` → `automation.graph` and persist
- [x] After migration: delete `sequence` field from stored JSON files
- [x] Version field: add `schemaVersion: 2` to AutomationData

### 4.2 Migration tests
- [ ] Test round-trip: legacy fixtures → migrate → graph → compile → VM runs correctly
- [ ] Test that v1.0 app opens pre-existing user profiles without errors

---

## Phase 5: Polish & Bug Fixes

### 5.1 Expression editor
- [x] Inline expression builder UI for common If/While/For/Switch fields
- [x] Autocomplete for variable names, port references, builtin functions
- [x] Syntax highlighting in expression text input
- [x] Validation feedback for common expression fields

### 5.2 Node editor UX
- [x] Keyboard `Delete` key handler for selected nodes/edges
- [x] Multi-select (Shift+click or box select) → bulk delete
- [x] Copy/paste nodes (Ctrl+C/V) with edge reconnection
- [x] Undo/redo stack (Ctrl+Z / Ctrl+Shift+Z) per automation
- [x] Snap-to-grid option (toggle in toolbar)
- [x] Auto-layout algorithm for messy graphs
- [x] Minimap for large graphs

### 5.3 Execution visualization
- [x] Highlight active node during test-run (pulse animation)
- [x] Show execution time per node after test-run completes
- [x] Error node highlight (red glow) when action throws
- [x] Breadcrumb trail showing execution path

### 5.4 Subgraph improvements
- [x] Subgraph parameters editor (name, type, default value)
- [x] Input/output port rendering on SubgraphCall nodes
- [x] Double-click SubgraphCall → focus subgraph details
- [x] Collapse selection into subgraph (refactoring tool)

### 5.5 Data wires
- [x] Visual data-wire drawing (separate from exec edges)
- [x] Type-safe data ports (color-coded by type)
- [x] Wire validation: prevent connecting incompatible types
- [x] Show invalid direct-drop feedback while hovering an incompatible data port.
- [x] Surface stale/invalid existing data wires in an editor health panel with one-click cleanup.
- [x] Keep implicit data-wire conversions disabled; type changes must go through explicit conversion nodes.
- [x] Add built-in conversion nodes for safe scalar and JSON conversions.
- [x] Show data flow values on hover during test-run

### 5.6 Performance & reliability
- [x] Compile-on-save with error reporting (don't wait until run)
- [x] Program cache invalidation (recompile only on graph change)
- [x] VM timeout per queue worker automation (configurable, default 30s)
- [x] Infinite loop detection beyond `maxIterations` returns visible test-run errors.
- [x] Abort propagation: cancel running actions cleanly on queue stop.

### 5.7 Misc fixes
- [x] Fix `@ts-ignore` usages across codebase (replaced with `@ts-expect-error` + descriptions)
- [ ] Remove dead code references to `castmate` naming (native binding names remain for compatibility)
- [x] Consolidate duplicate `NodeAutomationEdit.vue` if any remain in packages/castmate
- [x] Update `docs/graph-execution-engine.md` to reflect final implementation
- [ ] Bump version to `1.0.0-beta1` in all package.json files

### 5.8 Queue UX: Graph Scheduler, Not Separate Logic
- [ ] Keep queues as the runtime/scheduler for alerts, paid events, scene banners, and other non-overlapping stream moments.
- [ ] Hide queue complexity from everyday automation editing by controlling queues through graph-native nodes:
  - [x] `Add to Queue`
  - [x] `Queue Item Started`
  - [x] `Complete Queue Item`
  - [x] `Cancel Queue Item`
  - [x] `Clear Queue`
- [x] Treat queue worker automations as normal graphs: a queue item starts a graph, the graph drives overlays/sounds/OBS, then completes or cancels the item.
- [ ] Simplify the sidebar around the streamer workflow:
  - `Automations`
  - `Queues`
  - `Overlays`
  - `Variables`
  - `Integrations`
- [x] Make the `Queues` page observational first: show configured queues, the currently running item, pending items, recent completed/cancelled items, and the automation graph used when an item starts.
- [x] Add queue node styling in the automation editor so queue nodes are visually distinct from triggers, filters, overlays, paid alerts, and scene actions.
- [x] Add queue preview/debug visibility for queue action nodes through test-run path, result badges, and per-node durations.
- [x] Add starter templates for paid alerts and scene banners from `File -> New Automation From Starter`.
- [x] Add queue-worker starter templates:
  - `Paid Event -> Add to Alerts Queue`
  - `Queue Item Started -> Paid Alert Overlay -> Sound -> Complete`
  - `Scene Begin -> Add to Scene Queue`
  - `Queue Item Started -> Scene Banner -> Shader Layer -> Complete`
- [x] Document the mental model: queues remain powerful, but users should experience them as graph scheduling nodes rather than a second automation system.

### 5.9 Integrations, Plugin Visibility & Sidebar Preferences
- [x] Group plugins under `Integrations` categories instead of showing them as a flat secondary system.
- [x] Add per-plugin on/off toggles with green enabled and red disabled states.
- [x] Hide disabled plugin actions/triggers from automation context menus and command palettes.
- [x] Keep existing automations renderable even when their plugin is hidden from new-node menus.
- [x] Move native integrations (Twitch, YouTube, OBS, Moderation) into integration categories while allowing direct native shortcuts to be hidden.
- [x] Add plugin detail pages with overview, usage, settings, actions, triggers, and state tabs.
- [x] Add `Settings -> Interface` preferences for compact sidebar, disabled integration visibility, native shortcut hiding, category collapse defaults, and sidebar plugin switches.
- [ ] Add search/filter to integration categories and plugin detail pages once plugin count grows further.
- [ ] Add an optional "show hidden plugins" hint in automation search when a query matches only disabled plugins.
- [ ] Decide whether plugin visibility should remain local UI preference or become project/profile-level configuration.
- [ ] Expose plugin-specific diagnostics/config editors where a plugin currently relies on implicit resource state.

### 5.10 Updates, Settings & App Shell
- [x] Add in-app updates page with current version, latest version, release notes, and update action.
- [x] Treat missing `dev-app-update.yml` as a development-build state instead of a user-facing hard failure.
- [x] Sanitize release notes before rendering in the update page.
- [x] Return structured release note data from core update metadata instead of raw HTML.
- [x] Stabilize blank Settings page layout and add useful interface preferences.
- [x] Clean up Updates page layout so controls align and content stays inside the page shell.
- [ ] Add packaged-build smoke test for update metadata, release notes, and update availability.
- [ ] Add graceful offline/timeout messaging for update checks.
- [ ] Add a release-notes empty state that explains development builds without exposing file paths.

### 5.11 PR Review Fixes & Reliability
- [x] Cache rendered port positions for data-wire drawing/dragging to avoid repeated DOM queries and layout thrashing.
- [x] Preserve trigger and subgraph output data wires during health checks and cleanup.
- [x] Prevent terminal control nodes (`Return`, `Break`, `Continue`) from reconnecting to the previous downstream node during flow insertion.
- [x] Place context-menu-created action nodes at the click position even when the menu was opened from an existing node.
- [x] Make string-to-number conversion treat empty strings as invalid and use the fallback.
- [x] Make JSON stringify conversion always return valid JSON (`null` on unsupported/cyclic values).
- [ ] Add focused tests for terminal flow insertion and context-menu placement.
- [ ] Add a larger-graph performance smoke test for data-wire drag/render behavior.

### 5.12 Next Polish / Bug Fix Backlog
- [x] Add focused UI tests for automation context-menu search, including collapsed groups and disabled plugins.
- [x] Add conversion-node runtime tests for scalar parsing, JSON parsing, and fallback behavior.
- [x] Add visible invalid-drop feedback when the pointer is directly over an incompatible data port.
- [x] Surface stale/invalid existing data wires in an editor health panel with a one-click cleanup action.
- [x] Reduce remaining settings/plugin initialization console noise.
- [x] Audit action result schemas so every useful output is exposed as a typed data port.
- [x] Add node-menu categories for data transforms, overlays, queues, OBS, chat, and utility actions.
- [x] Add keyboard-first command menu navigation: up/down, enter, escape, and section shortcuts.
- [x] Add onboarding starter graphs for OBS scene changes, chat commands, moderation actions, and stream-plan events.
- [x] Add manual regression checklist for queue starter templates, conversion nodes, hidden plugins, and incompatible wires.
- [x] Replace automatic graph lanes with user-created colored annotation blocks in the node editor view.
- [ ] Add manual visual QA checklist for Settings, Updates, Integrations, plugin details, and automation context menu layout.
- [ ] Add persisted UI preference reset action in Settings.
- [ ] Add empty-state copy for integration categories with no visible plugins after filtering/hiding.
- [ ] Audit all remaining production `console.*` output after the beta polish pass.
- [ ] Audit remaining `@ts-expect-error` comments and remove any that are no longer needed.

### 5.13 Shader Graph Procedural Scene Roadmap
- [x] Keep Shader Graph inside the docked tab layout and use the automation-style context menu for non-input nodes.
- [x] Show only input/uniform/source nodes in the left rail; add all other nodes from the canvas context menu.
- [x] Add procedural noise nodes: Value Noise, Perlin Noise, FBM Noise, Voronoi, and Domain Warp.
- [x] Add terrain pipeline nodes: height map shaping, normals from height samples, slope/curvature masks, and erosion-like filters.
- [x] Add color ramp and biome helpers: gradient ramps, altitude bands, mask blending, grass/rock/snow bands.
- [x] Add lighting nodes: sun direction, diffuse/specular, ambient, fog, simple shadow, and ambient occlusion helpers.
- [x] Add camera/raymarching nodes: camera uniforms, ray direction, SDF primitives, raymarch sphere, and depth fade helpers.
- [x] Expand uniform controls: slider/color/vec2/vec3 UI, persisted defaults, and shaderUniforms config values that automation/widget bindings can target.
- [x] Add a real live WebGL preview with time/resolution/mouse uniforms and clear compile/runtime errors.
- [x] Add performance controls: resolution scale, max steps, quality presets, preview FPS throttle.
- [x] Add shader starter graphs: Procedural Terrain, Nebula, Audio Reactive, and Energy Field.
- [x] Add graph UX utilities: copy/paste, duplicate, reroute nodes, frames/comments, minimap, and fit selection.
- [x] Add shader function sampling foundation so terrain height/normal logic can be evaluated at multiple UV offsets.
- [ ] Extend shader function sampling from built-in terrain functions to reusable user-authored subgraphs.
- [x] Add preview controls: pause/resume, reset time, background mode, and clearer runtime error overlay.
- [ ] Add detachable or full-size shader preview mode for inspecting procedural scenes.
- [x] Add first-pass runtime shader uniform bindings through widget config paths and plugin state paths.
- [ ] Add specialized shader uniform binding pickers for automation variables, viewer variables, audio levels, and queue payloads.
- [x] Add typed node inspector controls for float, vec2, vec3/color, and vec4 input defaults.
- [x] Add multi-stop color ramp editor with persisted ramp stops and generated GLSL.
- [x] Add richer node inspector controls: units and min/max clamps.
- [x] Add shader graph undo/redo.
- [x] Add save/load/delete graph preset workflows directly inside the shader graph editor.
- [x] Keep shader graph nodes low-level and composable; avoid one-shot scene/terrain generator nodes.
- [x] Add low-level shader primitives: ridged FBM, turbulence, curl noise, cellular F1/F2, bias/gain, posterize, and remap helpers.
- [x] Add low-level material helpers: normal transforms, triplanar-style coordinates, layer masks, and simple BRDF pieces.
- [x] Add shader graph multi-select, box select, and move-selection behavior.
- [ ] Add advanced graph UX: resize frames, reroute from wire double-click, and wires-preserving clipboard.
- [x] Add first-pass compiler diagnostics for dead nodes and disconnected Fragment Output color.
- [ ] Add advanced compiler diagnostics: node/port-highlighted errors and safe GLSL expression nodes.
- [ ] Add runtime integrations: audio-reactive uniforms, mouse/viewer interaction uniforms, OBS/browser source size sync, preset import/export with thumbnails.

---

## Phase 6: Beta Stabilization Plan

### 6.1 Must Fix Before Beta
- [ ] Add tests for terminal flow insertion so `Return`, `Break`, and `Continue` never get outgoing edges when inserted into an existing flow.
- [ ] Add tests for context-menu node placement from canvas, node, edge, and pending flow contexts.
- [ ] Verify migration/opening behavior for old automations with stale `sequence`, `floatingSequences`, variable nodes, and data wires.
- [ ] Run packaged app smoke test for Settings, Updates, Integrations, starter templates, and graph editor.
- [ ] Confirm disabled plugins are hidden from new-node menus but existing nodes still render and save.
- [ ] Confirm update checks behave cleanly in development, offline, no-update, update-available, and downloaded states.

### 6.2 Should Fix Before Beta
- [ ] Add integration search/filter across grouped plugin categories and plugin detail tabs.
- [ ] Add "hidden plugin match" hint in automation context-menu search.
- [ ] Add Settings reset controls for interface preferences and plugin visibility.
- [ ] Tighten plugin detail page density for actions/triggers with many ports.
- [ ] Add visual regression screenshots or Playwright smoke coverage for Updates, Settings, Integrations, and node editor context menu.
- [ ] Finish console-noise audit in drag/drop, renderer startup, media, satellite, and plugin initialization paths.
- [ ] Finish low-risk `@ts-expect-error` cleanup pass.

### 6.3 Nice To Have After Beta
- [ ] Decide whether plugin visibility should be local-only, profile-level, or project-level.
- [ ] Add import/export for queue workflow starter templates.
- [ ] Add integration diagnostics panels for plugin resource/config state.
- [ ] Add large-graph performance profiling for minimap, data wires, selection, and auto-layout.
- [ ] Add richer queue observability: retry/cancel reason, worker graph link, and per-item execution timeline.

### 6.4 V2 Graph Model Improvements
- [x] Add a backwards-compatible `triggerNodes` schema/migration foundation that mirrors legacy root trigger data.
- [x] Render explicit trigger nodes when present while preserving the legacy virtual `trigger` node fallback.
- [x] Resolve data wires from explicit trigger node ids against the active trigger execution context.
- [x] Compile graph executions from a specific trigger node edge so independent trigger branches can start separately.
- [x] Expose trigger nodes from profile automations as invokable runtime trigger entries.
- [x] Allow selected trigger nodes to be configured in the node editor and add new trigger nodes from the context menu.
- [ ] Replace the single root `plugin`/`trigger` automation fields with a trigger-node collection while keeping a migration path for existing automations.
- [ ] Model each trigger as a visible graph node with stable id, plugin id, trigger id, config, context schema, and output data ports.
- [ ] Allow multiple trigger nodes in one automation graph, each with an independent execution entry edge.
- [ ] Run simultaneous trigger activations as separate automation executions so branches can proceed in parallel without sharing mutable trigger context.
- [ ] Scope trigger context data wires to the specific trigger node that produced them instead of the current global `trigger` virtual source.
- [ ] Add graph validation for multi-trigger entry edges, missing trigger definitions, duplicate trigger ids, and stale data wires.
- [ ] Add migration from legacy `trigger` virtual node wires to the first generated trigger node.
- [ ] Update starter templates to create explicit trigger nodes instead of relying on the implicit root trigger.
- [ ] Update command-menu UX so `Add Trigger` creates a new trigger node, while action insertion continues to work from canvas, edge, or node context.
- [ ] Add runtime tests for independent trigger executions, concurrent runs, data-context isolation, and disabled-plugin rendering behavior.
- [ ] Add editor tests for selecting, configuring, deleting, copying, and reconnecting multiple trigger nodes.
- [ ] Extend manual annotation blocks with optional persisted membership, drag-selected-nodes-into-block, collapse/expand, and move-with-group behavior.

---

## Phase 7: Release Prep

- [x] Update `DEVELOPERS.md` with new graph engine architecture
- [x] Write `MIGRATION.md` guide for existing users
- [x] Open beta polish PR against `main`
- [ ] Update `release.config.cjs` for major version bump
- [ ] Tag `v1.0.0-beta1` for testing
- [ ] Run full E2E: create automation, add control flow, test-run, save, reopen, verify
- [ ] Announce breaking change in changelog
- [ ] Prepare release notes for graph-only architecture, queue starters, integrations visibility, conversion nodes, and update UI.

---

## File Deletion Summary

| File | Reason |
|------|--------|
| `libs/showrunner-core/src/queue-system/sequence.ts` | Old runner, replaced by GraphVM |
| `libs/showrunner-core/src/queue-system/__tests__/sequence.test.ts` | Tests for deleted runner |
| `libs/showrunner-core/src/graph-engine/migration.ts` | Bridge code, no longer needed post-migration |
| `libs/showrunner-core/src/graph-engine/__tests__/migration.test.ts` | Tests for deleted migration |
| `libs/showrunner-ui-core/src/components/automation/OffsetSequenceEdit.vue` | Offset concept removed |
| `libs/showrunner-ui-core/src/components/automation/TimeActionEdit.vue` | Replaced by delay node config |

## Renames

| Old | New |
|-----|-----|
| `SequenceDebugger` | `ExecutionDebugger` |
| `SequenceResolvers` | `ActionResolvers` |
| `SequenceContext` | `ExecutionContext` |
| `SequenceSource` | `AutomationSource` |
| `QueuedSequence` | `QueuedAutomation` |
| `SequenceProvider` | `AutomationProvider` |
