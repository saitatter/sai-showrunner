# ShowRunner v1.0 - Remaining Implementation Roadmap

Completed work has been removed from this roadmap. The current Flutter status,
architecture, and migration disposition are documented in
[`docs/flutter-migration-plan.md`](flutter-migration-plan.md).

Electron remains the supported desktop entry point until the cutover gates in
this document pass. Flutter is the migration target; browser-native overlay and
WebGL surfaces remain web-owned unless a later decision changes that boundary.

## 1. Graph Compatibility Cleanup

- [ ] Delete `libs/showrunner-core/src/graph-engine/migration.ts` and its tests
      once all legacy consumers are gone.
- [ ] Remove the remaining `cloneActionForNodeEditor()` sequence-cloning path.
- [ ] Remove the unused `SubFlow` import from `ActionConfigEdit.vue`, if it is
      still present after the legacy editor cleanup.
- [ ] Keep the pre-v1.0 `old-migration.ts` path until all supported legacy data
      has a graph conversion path.
- [ ] Add a legacy fixture round-trip test: load, migrate, compile, execute,
      and persist an automation containing sequence, nested-stack, offset,
      variable-node, and data-wire data.
- [ ] Add a profile-opening test that exercises pre-v1.0 user data without
      renderer errors.
- [ ] Remove remaining dead `castmate` names where compatibility does not
      require them.
- [ ] Bump package versions to `1.0.0-beta1` when the beta release is cut.

## 2. Flutter Runtime and Product Parity

- [x] Implement the concrete Windows `SoundOutput` backend for file playback.
- [x] Add physical sound-device enumeration and output selection.
- [x] Add Windows WAV synthesis for installed system voices.
- [ ] Add parity for external TTS providers.
- [x] Add the viewer-variable lazy table with paging and sorting.
- [x] Add live provider synchronization for viewer data.
- [x] Add SQLite import support and non-primitive viewer-variable types.
- [ ] Reach native global-input parity in the Flutter runtime.
- [ ] Complete deeper bespoke Twitch, OBS, Moderation, Spellcast, and Dashboard
      workflows beyond the current foundations; Twitch channel-point reward
      CRUD and redemption status management are now covered in Flutter.
- [ ] Complete the remaining satellite replacement boundary, including media
      transfer and the rest of the remote widget catalog.
- [ ] Close the remaining exact Vue graph interactions listed in the migration
      parity audit.
- [x] Reuse the complete Flutter graph editing surface for Profile and Stream
      Plan transition automations, including segment-level graphs.

## 3. Editor, Integrations, and Settings Backlog

- [ ] Add focused tests for context-menu placement from node and pending-flow
      contexts; canvas and flow-edge placement are already covered.
- [ ] Add a larger-graph performance smoke test for data-wire drag and render
      behavior.
- [x] Add integration search/filtering across grouped categories and plugin
      detail tabs.
- [x] Add a hidden-plugin match hint when a search only matches disabled
      plugins.
- [ ] Decide whether plugin visibility is local UI preference or
      profile/project configuration.
- [ ] Expose plugin-specific diagnostics and configuration editors where plugin
      state is still implicit.
- [x] Add a persisted UI-preference reset action in Settings.
- [x] Add empty-state copy for integration categories with no visible plugins.
- [ ] Add a manual visual QA checklist for Settings, Updates, Integrations,
      plugin details, and the automation context menu.
- [ ] Audit remaining production `console.*` output.
- [ ] Audit remaining `@ts-expect-error` comments and remove obsolete ones.

## 4. Shader and Browser-Native Surfaces

- [ ] Extend shader function sampling from built-in terrain functions to
      reusable user-authored subgraphs.
- [ ] Add detachable or full-size shader preview mode.
- [ ] Add specialized shader uniform binding pickers for automation variables,
      viewer variables, audio levels, and queue payloads.
- [ ] Add advanced graph UX for resizeable frames, wire rerouting, and
      wires-preserving clipboard operations.
- [ ] Add compiler diagnostics that identify the failing node/port and support
      safe GLSL expression nodes.
- [ ] Add runtime bindings for audio-reactive uniforms, mouse/viewer
      interaction, OBS/browser-source size, and preset import/export with
      thumbnails.

## 5. Beta Validation and Cutover Gates

- [ ] Capture the remaining baseline smoke checks for startup, profile
      selection, integrations, automations, overlays, updates, and shutdown.
- [ ] Complete migration/opening fixtures for stale variable nodes and data
      wires in addition to the existing sequence conversion coverage.
- [ ] Run packaged-app smoke coverage for Settings, Updates, Integrations,
      starter templates, and the graph editor.
- [ ] Confirm disabled plugins stay out of new-node menus while existing nodes
      continue to render and save.
- [ ] Verify update checks in development, offline, no-update,
      update-available, and downloaded states.
- [ ] Add visual regression or Playwright coverage for Updates, Settings,
      Integrations, and the node-editor context menu.
- [ ] Run the full end-to-end workflow: create automation, add control flow,
      test-run, save, reopen, and verify.
- [ ] Validate install, update, and rollback for the packaged Flutter artifact
      before renderer cutover.
- [x] Validate first-run/data migration and clean shutdown for the packaged
      Flutter artifact with the scenario-aware Windows smoke harness.
- [ ] Remove the legacy Electron renderer only after the replacement boundary,
      release, install/update, and rollback evidence is complete.
- [ ] Remove stale locked `release/win-unpacked` output after the owning
      Electron process exits.

## 6. V2 Graph Model

- [ ] Replace the single root `plugin`/`trigger` fields with a trigger-node
      collection while retaining migration for existing automations.
- [ ] Model each trigger as a visible node with stable id, plugin id, trigger
      id, config, context schema, and output data ports.
- [ ] Allow multiple trigger nodes with independent execution entry edges.
- [ ] Run simultaneous trigger activations as isolated concurrent executions.
- [ ] Scope trigger data wires to the trigger node that produced the data.
- [ ] Validate multi-trigger entry edges, missing definitions, duplicate ids,
      and stale data wires.
- [ ] Migrate legacy virtual-trigger wires to the first generated trigger node.
- [ ] Update starter templates and command-menu `Add Trigger` behavior for
      explicit trigger nodes.
- [ ] Add runtime coverage for independent executions, concurrency, context
      isolation, and disabled-plugin rendering.
- [ ] Add editor coverage for selecting, configuring, deleting, copying, and
      reconnecting multiple trigger nodes.
- [ ] Extend annotation blocks with persisted membership, drag-to-block,
      collapse/expand, and move-with-group behavior.

## 7. Release Preparation

- [ ] Update `release.config.cjs` for the major beta version.
- [ ] Run the release E2E and artifact smoke gates on the final candidate.
- [ ] Announce the graph-only breaking change in the changelog.
- [ ] Prepare release notes covering graph execution, queue starters,
      integration visibility, conversion nodes, and update UI.
- [ ] Tag `v1.0.0-beta1` only after the cutover gates pass.
