# ShowRunner v1.0 — Graph-Only Engine (Breaking Change)

Completely remove `SequenceRunner` and the old sequence model. All automations run exclusively through `GraphCompiler` → `GraphVM`.

---

## Phase 1: Remove Old Sequencer (Core)

### 1.1 Relocate shared types
- [ ] Move `SequenceDebugger` interface from `sequence.ts` → `libs/showrunner-core/src/graph-engine/types.ts`
- [ ] Move `SequenceResolvers` (rename to `ActionResolvers`) → `libs/showrunner-core/src/queue-system/resolvers.ts`
- [ ] Keep `SequenceContext`, `SequenceSource`, `QueuedSequence` in schema (rename to `ExecutionContext`, `AutomationSource`, `QueuedAutomation`)
- [ ] Update all imports across the codebase

### 1.2 Delete old runner
- [ ] Delete `libs/showrunner-core/src/queue-system/sequence.ts` (SequenceRunner class)
- [ ] Delete `libs/showrunner-core/src/queue-system/__tests__/sequence.test.ts`
- [ ] Remove `SequenceRunner` export from `libs/showrunner-core/src/index.ts`

### 1.3 Simplify action-queue.ts
- [ ] Remove dual-path: `runNext()`, `queueOrRun()`, `runTestSequence()` use only GraphVM
- [ ] Remove `private runner: SequenceRunner | null` field
- [ ] Remove `private testSequences = new Map<string, SequenceRunner>()`
- [ ] Require `automation.graph` — throw if missing (fail-fast in dev)

### 1.4 Delete migration bridge
- [ ] Delete `libs/showrunner-core/src/graph-engine/migration.ts`
- [ ] Delete `libs/showrunner-core/src/graph-engine/__tests__/migration.test.ts`
- [ ] Remove exports from `libs/showrunner-core/src/graph-engine/index.ts`

---

## Phase 2: Schema Cleanup

### 2.1 Remove old sequence types
- [ ] Remove from `libs/showrunner-schema/src/types/sequence.ts`:
  - `Sequence`, `FloatingSequence`, `ActionStack`, `TimeAction`, `FlowAction`, `InstantAction`
  - `OffsetActions`, `TimeActionInfo`, `SubFlow`
  - `isActionStack()`, `isFlowAction()`, `isTimeAction()`, `isInstantAction()`
  - `getActionById()`, `getActionAndPathById()`, `assignNewIds()`, `getSequenceResultVariables()`, `getActionResultVariables()`
- [ ] Keep (possibly rename): `ActionInfo`, `SequenceContext` → `ExecutionContext`, `SequenceSource` → `AutomationSource`, `QueuedSequence` → `QueuedAutomation`, `SequenceProvider` → `AutomationProvider`

### 2.2 Simplify AutomationData
- [ ] Remove `sequence: Sequence` field — `graph: AutomationGraph` becomes mandatory
- [ ] Remove `floatingSequences: FloatingSequence[]` — subgraphs replace this
- [ ] Update `createInlineAutomation()` to return empty graph: `{ graph: { nodes: [], edges: [], entryNodeId: "" }, subgraphs: [] }`
- [ ] Remove `findActionById()`, `findActionAndSequenceById()`, `getActionByParsedPath()` traversal helpers

### 2.3 Update queues.ts
- [ ] Replace `QueuedSequence` → `QueuedAutomation` in `ActionQueueState`
- [ ] Update `ActionQueueConfig` types

---

## Phase 3: UI Cleanup (NodeAutomationEdit.vue)

### 3.1 Remove legacy rendering path
- [ ] Remove `isActionStack`, `isFlowAction`, `isTimeAction` imports & usage
- [ ] Remove `addSequence()` function and all `Sequence | FloatingSequence` processing
- [ ] Remove old node-building code that iterates `ActionStack`, `TimeAction`, etc.
- [ ] Remove `addFloatingSequence()`, `deleteFloatingSequence()`, `runFloatingSequence()`
- [ ] Remove `cloneActionForNodeEditor()` (old sequence cloning logic)

### 3.2 Graph-only buildGraph()
- [ ] `buildGraph()` always uses `buildGraphFromAutomationGraph()`
- [ ] Remove fallback path that builds nodes from `automation.sequence`
- [ ] Simplify `edges` computed — no conditional branch

### 3.3 Cleanup other UI files
- [ ] `ActionConfigEdit.vue` — remove `SubFlow` import if unused
- [ ] `TimeActionEdit.vue` — remove or convert to graph-native time/delay node editor
- [ ] `OffsetSequenceEdit.vue` — likely removable entirely (offsets not in graph model)
- [ ] `automation-dragdrop.ts` — rewrite for graph nodes (no more `FloatingSequence`)

---

## Phase 4: Data Migration (one-time, on load)

### 4.1 Upgrade migration in old-migration.ts
- [ ] Keep existing `old-migration.ts` for pre-v1.0 data → graph conversion
- [ ] On app startup: auto-migrate any `automation.sequence` → `automation.graph` and persist
- [ ] After migration: delete `sequence` field from stored JSON files
- [ ] Version field: add `schemaVersion: 2` to AutomationData

### 4.2 Migration tests
- [ ] Test round-trip: legacy fixtures → migrate → graph → compile → VM runs correctly
- [ ] Test that v1.0 app opens pre-existing user profiles without errors

---

## Phase 5: Polish & Bug Fixes

### 5.1 Expression editor
- [ ] Inline expression builder UI for If/While/For/Switch conditions
- [ ] Autocomplete for variable names, port references, builtin functions
- [ ] Syntax highlighting in expression text input
- [ ] Validation (red border + error tooltip for invalid expressions)

### 5.2 Node editor UX
- [ ] Keyboard `Delete` key handler for selected nodes/edges
- [ ] Multi-select (Shift+click or box select) → bulk delete
- [ ] Copy/paste nodes (Ctrl+C/V) with edge reconnection
- [ ] Undo/redo stack (Ctrl+Z / Ctrl+Shift+Z) per automation
- [ ] Snap-to-grid option (toggle in toolbar)
- [ ] Auto-layout algorithm (dagre or elkjs) for messy graphs
- [ ] Minimap for large graphs

### 5.3 Execution visualization
- [ ] Highlight active node during test-run (pulse animation)
- [ ] Show execution time per node after test-run completes
- [ ] Error node highlight (red glow) when action throws
- [ ] Breadcrumb trail showing execution path

### 5.4 Subgraph improvements
- [ ] Subgraph parameters editor (name, type, default value)
- [ ] Input/output port rendering on SubgraphCall nodes
- [ ] Double-click SubgraphCall → navigate into subgraph
- [ ] Collapse selection into subgraph (refactoring tool)

### 5.5 Data wires
- [ ] Visual data-wire drawing (separate from exec edges)
- [ ] Type-safe data ports (color-coded by type)
- [ ] Wire validation: prevent connecting incompatible types
- [ ] Show data flow values on hover during test-run

### 5.6 Performance & reliability
- [ ] Compile-on-save with error reporting (don't wait until run)
- [ ] Program cache invalidation (recompile only on graph change)
- [ ] VM timeout per-automation (configurable, default 30s)
- [ ] Infinite loop detection beyond `maxIterations` (surface to user)
- [ ] Abort propagation: cancel running actions cleanly on queue stop

### 5.7 Misc fixes
- [x] Fix `@ts-ignore` usages across codebase (replaced with `@ts-expect-error` + descriptions)
- [ ] Remove dead code references to `castmate` naming (run-clean-youtube.ps1 \u2705 done)
- [ ] Consolidate duplicate `NodeAutomationEdit.vue` if any remain in packages/castmate
- [x] Update `docs/graph-execution-engine.md` to reflect final implementation
- [ ] Bump version to `1.0.0-beta1` in all package.json files

---

## Phase 6: Release Prep

- [ ] Update `DEVELOPERS.md` with new graph engine architecture
- [ ] Write `MIGRATION.md` guide for existing users
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
