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

### 5.9 Integrations & Plugin Visibility
- [x] List every loaded plugin under `Integrations -> Plugin Visibility`.
- [x] Add per-plugin visibility toggle for automation node menus.
- [x] Hide disabled plugin actions/triggers from automation context menus and command palettes.
- [x] Keep existing automations renderable even when their plugin is hidden from new-node menus.
- [ ] Add search/filter to the `Integrations -> Plugin Visibility` list once plugin count grows further.
- [ ] Add an optional "show hidden plugins" hint in automation search when a query matches only disabled plugins.
- [ ] Decide whether plugin visibility should remain local UI preference or become project/profile-level configuration.

### 5.10 Next Polish / Bug Fix Backlog
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

---

## Phase 6: Release Prep

- [x] Update `DEVELOPERS.md` with new graph engine architecture
- [x] Write `MIGRATION.md` guide for existing users
- [ ] Update `release.config.cjs` for major version bump
- [ ] Tag `v1.0.0-beta1` for testing
- [ ] Run full E2E: create automation, add control flow, test-run, verify
- [ ] Announce breaking change in changelog

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
