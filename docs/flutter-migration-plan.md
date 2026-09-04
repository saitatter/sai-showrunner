# Flutter Migration Plan

## Objective

Migrate the ShowRunner desktop application from the current Electron + Vue/TypeScript implementation to a Dart + Flutter application while preserving broadcaster workflows, graph runtime semantics, overlay delivery, and the Windows-first release path.

The migration should be incremental. The current application remains usable throughout the work, and each migrated surface must be independently testable before the next surface moves.

## Status Snapshot (2026-09-05)

The Flutter package has a working Windows-oriented vertical slice. The shell, Dart
schema and persistence modules, graph compiler/runtime, action queue, provider workers,
resource registry, plugin catalog, OAuth primitives, and the initial OBS/YouTube/Twitch/
Moderation workspaces are implemented. The full Flutter test suite passes and the
current `flutter analyze` run is clean.

The remaining work is concentrated in four areas:

- graph-editor product parity beyond the current `sai_nodes` adapter;
- complete overlay/widget editing and OBS browser-source controls; the current editor
	supports generic widget JSON configuration and preserves widget data;
- provider/plugin parity, especially deeper bespoke plugin UX; YouTube now exposes
	persisted OAuth token, expiry, and refresh-token diagnostics in its workspace;
- baseline comparison, packaged Windows validation, and renderer cutover.

The migration is not yet a complete replacement of the Vue product. The Flutter
shell now has top-level closable workspace tabs, a persistent grouped integrations
sidebar with enable/disable switches, searchable integration and interface preferences, and a
non-blocking first-run setup wizard for Twitch, YouTube, and OBS. These are complete
Flutter slices, but the old Electron renderer remains the supported desktop entry
point until the cutover gates below pass.

The Sound slice now includes direct system speech through `flutter_tts`, Windows
PCM/WAV playback and WAV synthesis for installed system voices, and an injectable
sound-output resolver that preserves legacy splitter fan-out, mute, volume
scaling, duplicate-route selection, and cycle protection. Non-WAV playback,
WASAPI endpoint routing, and external TTS providers remain open parity work.

Deletion rule: a Vue file is deleted only when its user-visible behavior is present
in Flutter, its runtime/build references are removed, and a focused test or smoke
check passes. Renderer packages that only contained no-op registration code have
already been retired under this rule. Active plugin renderers, satellite pages, and
browser-native overlay code remain until their replacement boundary is proven.

The unchecked items below are intentionally not treated as compile failures. Several are
validation or release gates, and a few overlap with work already delivered in Phase 2.
They should be closed only when the corresponding smoke or packaged-build evidence exists.

The graph adapter now preserves execution edges and typed data wires, including schema
node and link IDs, through load/save round-trips. The automatic graph fit is explicit so
headless persistence tests do not depend on a mounted Flutter render tree.

Fresh Flutter data directories are routed to the Setup workspace automatically. The
wizard persists provider settings and a `setupCompleted` marker; existing installations
keep the normal workspace and can reopen Setup from the rail.

Automation creation now offers six validated Dart starter templates for chat-to-queue,
chat-to-overlay, chat queue plus overlay, subscription alerts, scene banners, and OBS
scene changes, alongside a blank graph option. Legacy sequence actions are converted
to executable graph nodes during Dart loading, including nested stacks, offsets, and
sub-flows; malformed graph links can be repaired and the automation catalog refreshes
after the repair completes.
The graph toolbar also exposes the pinned package's selection clipboard operations for
copy, paste, cut, and deletion of selected nodes. Node context menus now use the
searchable, collapsible `sai_nodes 0.2.0` menu API while canvas and edge-drop menus
retain their compatibility path. The overlay editor now provides
visual CRUD for widget geometry and common styling fields while preserving additional
widget configuration.
OBS browser-source controls now support URL updates and cache-free refresh through the
configured WebSocket transport. The graph workspace also exposes a node palette for
the currently registered chat trigger, queue, and overlay prototypes, with searchable
insertion and a reactive selected-node details panel. A custom minimap now renders the
graph node positions independently of `sai_nodes`, supports click-to-navigate viewport
centering, and shows the current viewport rectangle and persisted graph frames. The
editor also provides deterministic auto-layout, dynamic plugin action/trigger catalog
insertion, and runtime execution highlighting. Plugin diagnostics now include health
checks for every registered plugin, alongside provider worker and queue state.
Dashboard resources now have a dedicated Flutter editor for the Vue-compatible
dashboard -> pages -> sections -> widgets hierarchy, including CRUD for each level.
Input configuration now includes native Windows mouse-button simulation alongside
keyboard capture and shortcuts. Spellcast resources have a structured Flutter
editor and its trigger is backed by the Dart event hub. Viewer variables now have
an operational Flutter panel for definition CRUD, per-viewer value editing, and
lazy paginated/sorted viewer tables. The Flutter resource repository also reads
and round-trips the existing YAML resource directories without requiring a data
conversion before editing. Spellcast now has a dedicated Flutter workspace with
local CRUD, remote API sync, resource recovery for the connected Twitch channel,
and a Dart Cloud PubSub lifecycle bridge with negotiation, reconnect, reinit, and
active-spell synchronization. The active profile trigger set is propagated from
the Flutter profile lifecycle into the Spellcast subscription set.

## Current Architecture

- Electron owns the desktop process, packaging, update flow, and native integrations.
- Vue/Vite packages provide the renderer and most interactive application pages.
- `libs/showrunner-core` contains runtime, queues, resources, webserver, and integration-facing services.
- `libs/showrunner-schema` defines shared data contracts.
- Plugins under `plugins/*` provide integration actions, triggers, resources, and renderer pages.
- Overlay widgets remain browser-based and are delivered through OBS browser sources.

### Migration Disposition

| Area | Disposition | Current state |
|---|---|---|
| Main shell, integrations, settings, setup, profiles, queues, automations, resources, diagnostics, logs | `migrate` | Flutter slices exist; dynamic document docking, full visual parity, and cutover validation remain. |
| OBS, Twitch, YouTube, Moderation | `migrate` | Dart runtime and initial bespoke workspaces exist; deeper controls and configuration parity remain. |
| Simple plugin manifests and generic resource editors | `migrate` | Flutter registry/resource editors cover the current supported subset. |
| Plugin-specific renderers for Input, Random, Sound, IoT, Spellcast, Variables, Dashboards, and device integrations | `migrate` | Still active in Electron or only partially represented in Flutter; do not delete yet. |
| Satellite dashboard and connection pages | `migrate` | Vue runtime remains active; Flutter remote/satellite replacement is not implemented. |
| OBS browser-source overlay and WebGL/shader surfaces | `keep web` | Browser-native runtime; retain web packages behind an explicit boundary. |
| Electron main process, native bindings, updater, and packaging | `keep until cutover` | Required by the current supported desktop entrypoint and release workflow. |

The current audit finds 313 active Vue files, including roughly 280 component
files, across shared UI, plugins, satellite, and browser-native overlay packages.
Their existence alone is
not a deletion defect: each remains until its disposition has a Flutter or web
replacement and no active build/runtime consumer.

## UI Parity Audit

This audit compares the former Vue automation editor responsibilities with the
current Flutter implementation. “Partial” means the core workflow exists but a
Vue interaction or visual detail is still missing; it is not a runtime failure.

| Surface | Flutter status | Owning layer and next step |
|---|---|---|
| Shell, navigation, workspace tabs, integration catalog, loading/empty/error states | Partial | Flutter app/features; top-level closable tabs, grouped plugin switches, searchable integration filtering, explicit disabled-plugin hints, Settings preferences, and first-run Setup exist. Dynamic document docking, split panes, persistence, baseline comparison, and accessibility coverage remain. |
| Canvas pan/zoom, grid, selection, multi-select, fit, alignment, distribution, history | Done | `sai_nodes`; keep generic controls in `NodeEditorToolbar`. |
| Typed control-flow and data ports, link persistence, invalid-link retention | Done | ShowRunner adapter plus `sai_nodes` link primitives; add broader widget coverage. |
| Palette, grouped insertion, search, recent node types, edge insertion | Partial | ShowRunner graph workspace; route palette actions through the generic searchable menu. The generic menu now supports keyboard traversal. |
| Node cards, fields, ports, execution badges, search dimming | Partial | ShowRunner builders over `sai_nodes`; generic instance title and opt-in resize behavior are available, while product visuals remain to be completed. |
| Node configuration and schema defaults | Partial | ShowRunner data-input layer; add inline configuration where the Vue card exposed it. |
| Trigger insertion, replacement, persisted metadata, trigger configuration | Partial | Plugin registry and graph adapter; verify every trigger schema in widget tests. |
| Context menus and shortcuts | Partial | Node menus use `sai_nodes 0.2.0` searchable/collapsible primitives with keyboard traversal; canvas and edge-drop compatibility menus and remaining ShowRunner palette entries still need migration. |
| Clipboard and internal-link restoration | Done | `sai_nodes` clipboard with ShowRunner metadata sidecar; retain round-trip tests. |
| Frames and annotations | Partial | ShowRunner frame model/overlay; finish drop/remove states and annotation interaction parity. |
| Minimap and viewport navigation | Partial | ShowRunner overlay; render flow/data links distinctly and test drag navigation. |
| Graph health, validation, recovery | Partial | ShowRunner recovery service now has per-issue stale-link cleanup and rejected-link feedback; add focused widget coverage. |
| Execution state, active path, node run, result inspection | Partial | Dart runtime plus graph overlays; add result schemas/output-port visualization and path details. |
| Variables and nested subgraphs | Done | ShowRunner adapter and dialogs; retain nested controller synchronization tests. |
| Plugin catalog, settings, health, OAuth, bespoke workspaces | Partial | Dart plugin registry; generic settings, persisted enable/disable, health, OAuth, and initial OBS/YouTube/Twitch/Moderation workspaces exist. Complete the remaining bespoke plugin workspaces and resource-specific behavior. |
| Overlay/widget/resource editors | Partial | Flutter resource registry; complete remaining widget configuration and browser/WebGL decisions. |
| Packaging, renderer cutover, rollback | Partial | Versioned Flutter archives now have an isolated Windows startup smoke wired into CI/release; install/update, first-run/data migration, Electron removal, and one-cycle rollback evidence remain. |

### Ownership Boundary

`sai_nodes` should remain responsible for generic graph mechanics: viewport
transforms, grid and zoom, node/link selection, typed port primitives, default
node rendering, keyboard/clipboard/history behavior, alignment, distribution,
auto-layout, and the toolbar/context-menu extension points.

ShowRunner should remain responsible for domain policy: persisted schema IDs and
payloads, plugin and trigger manifests, configuration schemas/defaults, runtime
execution, result mapping, variables, subgraphs, frames/annotations, graph
validation and invalid-link recovery, execution state, and the node palette.

The local `sai_nodes` `0.2.0` candidate contains the generic editor foundation:
searchable/collapsible menu sections with keyboard traversal, public node title
and resize APIs with an opt-in default handle, coalesced resize history,
semantic link endpoint fields, configurable link/port hit tolerances,
corrected hover-exit events, defensive restored link insertion, and optional
link labels with configurable rendering. ShowRunner consumes this candidate
through its hosted `^0.2.0` dependency after publication.
Do not add ShowRunner persistence or plugin semantics to the package. Keep the
ShowRunner migration behind its adapter and promote additional APIs only after
a focused widget test demonstrates that the existing public builder/event APIs
cannot support the behavior.

### Cleanup Debt

- Retired the no-op HTTP, Time, Stream Plans, DonorDrive, and Elgato renderer
	packages after removing their package, path-mapping, and initialization references.
- Removed the unreferenced main-renderer integration utilities, legacy SCSS theme
	system, and OBS setup screenshots. Keep `theme-ext.css`, fonts, logos, and
	`spellcast.css` while the Electron renderer still imports them.
- Generated directories such as `packages/showrunner-flutter/.dart_tool/`,
	`packages/showrunner-flutter/build/`, `dist/`, `dist-electron/`, and unpacked
	release output are disposable and must never be treated as source migration work.
	Preserve `user/` and `release/user/` because they contain runtime data.
	The Flutter package also ignores generated `.flutter-plugins`, `.packages`,
	`.flutter-plugins-dependencies`, and `windows/flutter/ephemeral/` files. Keep
	`pubspec.lock`, `.metadata`, and `windows/flutter/generated_*` because they are
	project or reproducibility inputs rather than build output.
- Split `graph_workspace.dart` into canvas composition, palette/context menus,
	node rendering, overlays/minimap, and details/configuration modules while
	preserving the current public `GraphWorkspace` entry point.
- Split `showrunner_graph_editor.dart` along persistence, node registry,
	clipboard, variables, subgraphs, frames, and execution state boundaries only
	where the adapter remains the single translation point.
- Keep generic graph actions in `sai_nodes`' toolbar; the shell AppBar owns only
	document, runtime, and ShowRunner-specific commands.
- Keep registry/bootstrap/resource editor definitions in their active organized
	paths; obsolete duplicate Flutter files have been removed.
- Add focused widget tests for each Partial row before marking it Done.

### Validation Gates

Run these gates from the repository before closing the migration batch:

1. `flutter analyze` and `flutter test` in `packages/showrunner-flutter`.
2. `flutter analyze` and `flutter test` in the local `sai_nodes` package.
3. `git diff --check` for whitespace and patch hygiene.
4. Focused widget tests for context-menu search/collapse, inline configuration,
   trigger configuration, graph-health repair, frame/annotation interactions,
   minimap navigation, and result-port visualization.
5. Windows smoke coverage for startup, opening and saving an automation,
   provider setup, graph execution, clean shutdown, and packaged artifact
   launch before renderer cutover. The startup/archive portion is provided by
   `scripts/smoke-flutter-windows.ps1`; the workflow scenarios remain open.

The first three gates prove the current source contracts. The focused widget and
Windows gates are required before claiming exact Vue parity or removing the
rollback path.

## Guiding Decisions

1. Port schema, persistence, runtime, queues, and plugin contracts to Dart instead of introducing an RPC layer between Flutter and TypeScript.
2. Prefer one Flutter desktop application with Dart feature modules over a parallel second desktop product.
3. Keep the overlay runtime web-based because OBS browser sources and WebGL are browser-native surfaces.
4. Support Windows first, matching the existing packaged release target.
5. Do not port Vue components line by line. Rebuild workflows around Flutter state, navigation, accessibility, and desktop input patterns.
6. Evaluate `sai_nodes` as the graph-editor foundation, behind a ShowRunner adapter so the package can be replaced without rewriting graph-domain code.

## Phase 0: Baseline and Scope

- [x] Record the current release/build/test commands and supported Windows versions.
- [ ] Capture baseline smoke checks for startup, profile selection, integrations, automations, overlays, updates, and shutdown.
- [x] Inventory renderer pages, global stores, Electron IPC calls, websocket clients, and plugin UI entry points.
- [x] Mark each surface as `migrate`, `keep web`, `replace`, or `defer`.
- [x] Agree on Flutter 3.44.0 stable, Dart SDK `^3.12.0`, and the Windows desktop embedding strategy.

**Exit gate:** the existing application has a repeatable baseline checklist and every user-facing surface has an owner and migration disposition.

## Phase 1: Dart Foundation and Architecture Spike

- [x] Create a minimal Flutter Windows app in a dedicated package or sibling workspace.
- [x] Use the published `sai_nodes` package in the spike and verify its Windows build.
- [x] Build a representative ShowRunner graph with trigger, action, condition, data ports, subgraph call, and queue nodes.
- [x] Map ShowRunner graph JSON to `sai_nodes` models through an internal adapter; do not expose package models outside the editor module.
- [x] Validate custom node builders, typed ports, directional execution edges, data wires, pan/zoom, multi-select, context menus, keyboard deletion, copy/paste, and graph serialization at the adapter/controller level.
- [x] Measure whether undo/redo, minimap, auto-layout, frames, and execution highlighting can be implemented cleanly around the package API.
- [ ] Create Dart packages for schema, persistence, runtime, queues, and plugin contracts under the Flutter migration workspace.
- [x] Port representative `showrunner-schema` types to Dart with explicit JSON round-trip tests.
- [x] Add a direct Dart automation JSON repository with filesystem round-trip coverage.
- [x] Add direct Dart services for plugin settings, resource configs, and filesystem health snapshots.
- [x] Port runtime health, settings, resource loading, and save operations as direct Dart services.
- [x] Add a small vertical slice: load settings from the existing data directory, display health, and persist one harmless setting change.
- [x] Port the graph expression evaluator and bounded Dart control-flow runtime with injectable actions.
- [x] Resolve trigger and node-result data wires into action configuration in the Dart runtime.
- [x] Map action results into runtime context state without mutating caller-owned input.
- [x] Add Dart plugin manifests, action registration, and registry-backed graph execution.
- [x] Port the first OBS action slice behind an injectable Dart transport.
- [x] Add the shared Dart capability contract for plugin settings, triggers, actions, and health.
- [x] Port the first YouTube chat and moderation action slice behind an authorized transport.
- [x] Add the Dart action queue with pause, skip, replay, execution, bounded history, timeout, cancellation, and change notifications.
- [x] Add a real OBS WebSocket v5 transport with authentication and request correlation.
- [x] Add the first Dart graph compiler IR with reachability validation, node source mapping, and port targets.
- [x] Add a bounded compiled graph executor for action, branch, passthrough, and return instructions.
- [x] Add bounded compiled while, for, and forEach execution plus explicit break/continue instruction targets.
- [x] Add compiled subgraph bundles, recursive call frames, and per-instruction debugger step hooks.
- [x] Add queue JSON persistence, restoration, batch processing, configurable gaps, timeouts, and cancellation notifications.

**Spike note:** the initial automated coverage tests the `sai_nodes` adapter/controller contract directly. Widget lifecycle and Windows input coverage remain release gates because the package owns the canvas event loop.

**Exit gate:** the Dart app owns the vertical slice without a TypeScript process or RPC boundary. The graph spike passes the feature checklist or records a replacement decision before production editor work begins.

## Phase 2: Flutter Shell and Shared Foundations

- [x] Add Flutter window sizing, focus management, theming, and accessibility foundations.
- [x] Add an initial Flutter navigation shell with Graph, Plugins, and Diagnostics workspaces.
- [x] Add closable top-level workspace tabs and a persistent integrations sidebar.
- [x] Add searchable interface preferences with persisted plugin visibility controls.
- [x] Add a non-blocking first-run setup workspace for Twitch, YouTube, and OBS provider settings.
- [x] Render manifest-declared plugin settings in the Flutter Settings workspace with search and per-plugin persistence.
- [x] Add a dedicated Flutter Variables workspace with search, current-value editing, reset, and CRUD persistence.
- [x] Add Flutter catalog workflows for saved automations and profiles with loading, empty, and error states.
- [x] Load existing YAML automation files, expose graph metadata, and report invalid files individually.
- [x] Port profile schema and YAML-compatible persistence, including activation/deactivation automations.
- [x] Display parsed profile metadata and per-file validation errors in the Flutter shell.
- [x] Open persisted automations from the catalog in the `sai_nodes` graph editor, including unknown node prototypes.
- [x] Serialize edited `sai_nodes` positions and control links back into the Dart automation schema and save atomically.
- [x] Run the active automation through the Dart action queue and graph runtime from the Flutter shell.
- [x] Bootstrap OBS, YouTube, and Twitch action manifests in the Flutter registry with explicit transport configuration errors.
- [x] Select the real OBS WebSocket and authenticated YouTube/Twitch HTTP transports from provider settings, with unauthenticated fallbacks.
- [x] Add injectable Twitch EventSub WebSocket and YouTube Live Chat polling workers with normalized event hub output.
- [x] Start and stop configured provider workers with the Flutter shell lifecycle and pass Twitch Client-Id authentication.
- [x] Add a Flutter provider settings editor for OBS, YouTube, and Twitch with masked credentials and atomic YAML persistence.
- [x] Add Twitch EventSub exponential-backoff reconnect and reactive worker status in Diagnostics.
- [x] Add YouTube Live Chat error capture and bounded exponential polling backoff.
- [x] Add expiry-aware OAuth refresh for YouTube and Twitch, persist rotated tokens, and deduplicate concurrent refreshes.
- [x] Validate provider settings before persistence and retry transient OAuth server failures with bounded attempts.
- [x] Add OAuth authorization request primitives and refresh immediately when only a refresh token is available.
- [x] Add loopback OAuth callback handling, authorization-code exchange, state validation, and YouTube/Twitch authorization controls in the Flutter settings UI.
- [x] Migrate the Profiles catalog/editor to Flutter with profile creation, activation mode editing, trigger list editing, save, and delete operations.
- [x] Keep the `sai_nodes` renderer out of the headless shell smoke test; graph adapter and runtime behavior remain covered by dedicated tests.
- [x] Extract startup health and the `sai_nodes` graph adapter from the Flutter entrypoint into focused app/editor modules.
- [x] Extract the Graph workspace, health banner, migration settings panel, and graph status widget into a feature module.
- [x] Extract the Queue workspace, queue configuration editing, and runtime queue views into a feature module.
- [x] Extract the Profile editor and profile persistence workflow into a feature module.
- [x] Extract the Automation catalog and graph recovery actions into a feature module.
- [x] Extract the Resources workspace for overlays and variables into a feature module.
- [x] Extract the Logs and About workspaces into a support feature module.
- [x] Extract the Diagnostics workspace, provider worker status, and queue diagnostics into a feature module.
- [x] Extract the Plugins provider settings workspace, validation, persistence, and OAuth controls into a feature module.
- [x] Extract the application shell, navigation rail, workspace composition, and toolbar actions into a focused app module.
- [x] Organize graph adapter, startup health, automation recovery, and action queue tests under dedicated test domains.
- [x] Add a dedicated Flutter Queue workspace with live pending/running/history views and pause, resume, and clear controls.
- [x] Add the Dart queue configuration schema and YAML repository for name, pause state, gap, timeout, and preserved extra fields.
- [x] Migrate the named queue catalog and configuration CRUD to Flutter, then remove the Vue Queue page.
- [x] Port automation graph validation and repair to Dart and expose recovery from the Flutter automation catalog.
- [x] Add Flutter automation catalog creation, deletion confirmation, immediate editor opening, and repository coverage.
- [x] Expose shared Dart action queue state and pause/resume controls in Diagnostics.
- [x] Implement shared models for profiles, integrations, resources, automations, queues, overlays, and update state.
- [x] Implement lifecycle handling for loading, disconnected, reconnecting, offline, and fatal-error states.
- [x] Add structured logging and diagnostics visible from the Flutter shell.
- [x] Add golden/widget test conventions and a Windows smoke-test entry point.

**Exit gate:** Flutter can launch, navigate between placeholder routes, load Dart services, and report failures without crashing.

## Phase 3: Low-Risk Workflow Migration

Migrate surfaces with limited editing complexity first:

- [x] About and update pages data contracts and status models.
- [x] Settings and provider interface preferences.
- [x] Profile selection and profile repository basics.
- [x] Media, variables, and overlays schema & repository persistence.
- [x] Integration list, enable/disable state, health, and diagnostics.
- [x] Activity and log views backed by structured in-memory logger.

For each surface:

- [ ] Define Dart service methods and stream subscriptions.
- [ ] Port loading, empty, error, and disabled states.
- [ ] Add focused widget tests and one end-to-end smoke path.
- [ ] Compare behavior against the baseline checklist.

**Exit gate:** the Flutter shell supports daily setup and configuration workflows without opening the Vue renderer for those surfaces.

## Phase 4: High-Value Editing Workflows

- [x] Migrate overlay list, overlay editor, widget configuration, and OBS browser-source controls.
- [x] Port the shared media picker with recursive media discovery, type filtering, search, and overlay widget config persistence.
- [x] Add explicit Twitch EventSub connect/disconnect controls backed by the Dart provider worker.
- [x] Add Stream Plan resource persistence, ordered segment editing, Twitch segment metadata, and navigation actions.
- [x] Port reusable color, duration, and boolean input controls into Flutter resource and plugin editors.
- [x] Port the generic Flutter data-input controls for scalar values, enums, colors, durations, arrays, objects, files, and resources.
- [x] Port OBS scene, source, filter, media, audio, studio, replay, screenshot, transform, play-media, and hotkey actions, including legacy aliases.
- [x] Port Twitch Helix actions for ads, snoozing ads, predictions, chat announcements, shoutouts, stream info, polls, clips, markers, and moderation.
- [x] Map Twitch EventSub notifications to the Dart event hub for ads, predictions, polls, subscriptions, follows, redemptions, bits, raids, hype trains, and chat moderation.
- [x] Port the Moderation Docker chat decision action with legacy result normalization and operator activity feedback.
- [x] Migrate the automation catalog, starter selection, graph editing foundation, validation, save, and test-run feedback.
- [ ] Close the remaining exact Vue graph interactions listed in the UI parity audit.
- [x] Migrate queue observation and queue-worker diagnostics.
- [x] Port keyboard-first behavior, copy/paste, undo/redo, minimap, data-wire validation, and execution highlighting.
- [ ] Keep shader preview and other browser/WebGL surfaces in web views or dedicated web components until a performance decision is made.

**Exit gate:** a user can create and run a representative automation, inspect queue execution, and configure an overlay entirely from Flutter.

## Phase 5: Plugin and Integration Migration

- [x] Define a plugin capability manifest independent of Vue component registration.
- [x] Expose plugin metadata, actions, triggers, settings, runtime state, health, and diagnostics through Dart interfaces.
- [x] Port the first bespoke YouTube control slice: live chat ID, start/stop ingest, broadcast discovery, and chat simulation.
- [x] Add initial bespoke OBS and Twitch workspaces backed by the Dart registry and provider event runtime.
- [x] Add a Dart-owned Moderation plugin with settings, health, test event, queue, and operator override controls.
- [x] Add resource editor registration and persistence for Overlay, Variable, OBSConnection, RCONConnection, TTSVoice, and CustomTwitchViewerGroup.
- [x] Load and edit mapped plugin resources from Vue-compatible directories: `obs/connections`, `minecraft/connections`, `sound/tts`, and `twitch/groups`.
- [x] Add structured resource editors for OBS/RCON connections, TTS voices, and Twitch viewer groups, including TTS JSON config preservation.
- [x] Persist Moderation test-event counters in the Dart-owned service and make its transport injectable for deterministic tests.
- [x] Add Moderation queue buckets (`latest`, `pending`, `approved`, `rejected`), counters, and text/platform/verdict filters to the Flutter workspace.
- [x] Add a Dart-native Moderation dashboard WebSocket with token headers, reconnect handling, live status updates, and recent decisions.
- [x] Add bounded activity feeds to the Dart-owned YouTube Live Chat and Twitch EventSub surfaces.
- [x] Add direct OBS quick controls for scene changes, stream toggling, and recording toggling through the configured Dart WebSocket transport.
- [x] Add YouTube/Twitch OAuth diagnostics for token presence, expiry, and refresh-token availability.
- [x] Expose real YouTube chat/delete/ban controls and Twitch chat/marker/timeout controls through the configured Dart plugin registry.
- [x] Add create, edit, delete, and reload flows for all currently registered Flutter resource types.
- [x] Decouple plugin architecture so each plugin exposes its actions, triggers, settings, resources, and custom workspace UI via `workspaceBuilder` on `DartPluginManifest` without hardcoded checks in the application shell.
- [x] Decouple resource workspace so resource editor definitions dynamically register storage directories, default configurations, dialog builders, and CRUD flows.
- [x] Add Dart plugin manifests for `time`, `os`, `random`, `variables`, `overlays`, `spellcast`, and `iot` plugins and register them in the Dart plugin registry.
- [x] Port the OS PowerShell and application-launch action configuration into Flutter data-input schemas.
- [x] Retire the no-op HTTP and Time Vue renderer packages after their Dart manifests became authoritative.
- [x] Retire the no-op Stream Plans, DonorDrive, and Elgato Vue renderer packages after removing their workspace references.
- [x] Add closable workspace tabs for the top-level Flutter destinations.
- [x] Add a persistent left integrations catalog with plugin selection and enable/disable toggles.
- [x] Add integration search across grouped categories and registered plugin
	capabilities, including a hint when only disabled plugins match.
- [x] Add explicit empty-state copy for filtered integration categories and a
	persisted interface-preference reset action.
- [x] Delete migrated main-renderer Vue component directories for main page, integrations, setup, updates, migration, profile editor, queue page, test editors, about, settings, project/profiles, dashboard, system, and automation editor.
- [x] Achieve 0 analyzer issues across the entire `showrunner-flutter` codebase (`flutter analyze` clean).
- [x] Migrate YouTube status/OAuth diagnostics.
- [ ] Deepen full parity for Twitch, OBS, and Moderation bespoke workspaces.
- [x] Add a generic plugin detail page for capabilities that do not need bespoke UI.
- [ ] Port bespoke plugin pages only where the generic page is insufficient.
- [x] Port Input keyboard-key and key-combination capture controls and native
	keyboard/mouse actions before removing `plugins/input/renderer/`.
- [x] Port Variables definitions, current-value editing, reset flows, and CRUD
	persistence into the Flutter workspace.
- [x] Port the bounded viewer-variable definitions repository and the legacy
	`setViewerVar`/`offsetViewerVar` actions for Twitch IDs.
- [x] Port lazy viewer tables and the local viewer-data query surface; provider
	event synchronization and the remaining viewer-variable types remain before
	removing `plugins/variables/renderer/`.
- [x] Port Sound TTS voice and AudioSplitter configuration editors, plus the
	injectable direct-speech and splitter-routing runtime slices.
- [x] Port IoT color/brightness controls into the generic Flutter data-input
	boundary.
- [x] Port the Spellcast page, local resource recovery, and remote CRUD/sync
	controls into Flutter.
- [x] Port Spellcast cloud PubSub negotiation, reconnect, reinit, and
	active-spell lifecycle handling into the Dart event hub.
- [x] Drive Cloud PubSub active-spell subscriptions from the active profile's
	selected trigger set before removing the old renderer lifecycle hooks.
- [x] Port Windows PCM/WAV playback, playback trimming, volume control, and
	WinMM output enumeration into the Dart Sound runtime.
- [x] Port the OBS scene/source catalog, source/filter visibility toggles,
	JSON input-settings editing, and structured source transform editing into
	Flutter.
- [x] Complete Windows WAV TTS generation for installed system voices.
- [ ] Complete non-WAV Sound playback, WASAPI endpoint routing, and
	external-provider parity before removing its active renderer components.
- [ ] Complete structured OBS source configuration and Overlays widget/shader
	editing before removing `plugins/obs/renderer/` or
	`plugins/overlays/renderer/`.
- [x] Complete Twitch channel/account, stream info, prediction/poll, and
	group-management workflows; complete YouTube live status controls.
- [x] Complete Dashboards page/section/widget editing, widget JSON/size
	configuration, sharing IDs, and remote resource-slot configuration.
- [ ] Add device-specific resource settings for the remaining integrations.
- [ ] Replace the satellite connection/dashboard/settings/slots renderer with
	a Flutter remote workspace before removing `packages/showrunner-satellite/`.
- [ ] Keep plugin runtime code in existing packages until the new boundary is proven.

The Flutter plugin workspace now follows the original application's separation model: a registry-backed plugin catalog groups core integrations and platforms, while each selected plugin gets its own details surface. Provider credentials are generated from manifest-declared settings, and registered actions, triggers, and settings are exposed from the Dart manifest instead of being presented as one undifferentiated settings page. Plugin visibility is persisted in `user/settings/showrunner-flutter.yaml`, loaded into the Dart registry, and enforced when actions are invoked. Plugin details also expose automation usage and manifest-declared runtime state. Migrated plugin code now has per-plugin directories with `manifest.dart`, `runtime.dart`, `ui/`, and `resources/` boundaries, while legacy top-level files remain compatibility entry points. YouTube controls the real Dart live-chat worker, OBS exposes a registry-backed WebSocket health surface, Twitch exposes EventSub/chat activity, and Moderation owns its HTTP settings, health, queue, test-event, and override contracts. Resource editors are registered independently from manifests, persist Overlay and Variable data, and now load/edit plugin resources from Vue-compatible directories for OBS, Minecraft, Sound, and Twitch. Remaining work is deeper bespoke UX, input capture/native integration parity, satellite migration, and plugin-specific resource editor polish.

**Exit gate:** enabling a plugin, configuring its account/resource, and using its actions/triggers works from Flutter for the supported core integrations.

## Phase 6: Release Cutover and Retirement

- [ ] Run Flutter and the existing Vue shell in parallel only as a temporary comparison mode.
- [ ] Compare startup time, memory, input latency, reconnect behavior, and packaged size.
- [x] Produce a versioned Flutter Windows archive and verify that it contains the executable and bundled data directory.
- [x] Add packaged Windows startup and clean-shutdown smoke for the Flutter archive.
- [ ] Add packaged Windows smoke tests for install, update, first-run setup, and Dart data migration workflows.
- [ ] Make Flutter the default renderer only after the beta checklist passes.
- [ ] Keep a rollback switch for at least one release cycle.
- [ ] Remove remaining unused Vue renderer routes and temporary compatibility code in separate, validated cleanup batches.
- [x] Update README, developer setup, release workflows, and migration documentation for the Flutter startup smoke gate.

**Exit gate:** Flutter is the supported desktop UI, rollback is no longer required, and removed Vue surfaces have no remaining runtime or build references.

## Technical Workstreams

### Dart Runtime and Persistence

- Port runtime ownership directly to Dart, preserving graph compiler, VM, queue, resource, and persistence semantics.
- Use Dart streams and cancellable operations for in-process events instead of RPC envelopes.
- Keep JSON compatibility with existing user data while the Dart schema becomes authoritative.

### Graph Editor

- Treat `sai_nodes` as an implementation detail behind a `ShowRunnerGraphEditor` adapter.
- Keep ShowRunner's `AutomationGraph`, node definitions, port types, subgraphs, and validation rules authoritative.
- Use package serialization only as an editor-state transport; persisted user data continues to use ShowRunner schema contracts.
- Pin the dependency version during the spike and review upstream changes before upgrades.
- Replace the package if it cannot support required desktop interactions, performance, accessibility, or graph fidelity without invasive patches.

#### sai_nodes parity assessment

The current public `sai_nodes 0.2.0` API is sufficient for the editor foundation: custom node prototypes, typed control/data ports, field prototypes, node/link styles, viewport controls, selection, history, clipboard shortcuts, alignment, distribution, auto-layout hooks, selection/clipboard/viewport events, and searchable/collapsible node menus are available through the package barrel.

The existing Vue editor still has several product-level surfaces that are not generic renderer responsibilities: custom node cards with configuration summaries and execution badges, plugin-driven context menus, data-wire health overlays, minimap navigation, annotation blocks, subgraph breadcrumbs, and the full details/configuration panel. These belong in the ShowRunner adapter and surrounding Flutter widgets. A fork or local patch to `sai_nodes` is justified only if the default node renderer or canvas event routing prevents those widgets from being composed without modifying package internals.

Near-parity decision: keep the local dependency and build a ShowRunner-owned editor shell around it; do not fork yet. Propose generic upstream additions only after a focused widget test demonstrates a concrete missing public hook, and keep any compatibility fork behind the same adapter boundary.

The first visual spike is complete: the Flutter graph workspace now uses the public header, field, and port builders while preserving `sai_nodes` interaction wrappers. Queue and overlay action prototypes expose editable String configuration fields, hydrate them from ShowRunner node data, and synchronize submitted values back to the persisted graph model. The full custom `NodeBuilder` remains intentionally unused until its interaction wrapper requirements are covered.

### State and Persistence

- Move persistence ownership to Dart once the relevant schema models are ported.
- Treat Flutter state as a projection of Dart domain services, with explicit refresh and optimistic-update rules.
- Reuse schema versions and migration rules; never let the new UI silently fork persisted data formats.

### Plugin Model

- Port plugin capability discovery, settings, actions, triggers, and permissions to Dart interfaces.
- Keep each integration behind a Dart plugin interface and provide generic Flutter settings rendering where possible.
- Port integrations in slices, starting with settings and read-only health before live event handling.
- Current Dart slices include OBS, YouTube, Twitch, Moderation, Discord, Sound,
	Minecraft, HTTP, time, OS, random, variables, overlays, Spellcast, IoT, and
	Stream Plans manifests. Twitch and YouTube expose in-process trigger streams
	through a shared Dart event hub, with provider workers started by the shell.
- Remaining plugin work is bespoke UX depth, especially status/OAuth diagnostics
	and integration-specific pages not covered by generic manifests.

### Overlays and Web Content

- Continue serving OBS overlays as browser sources.
- Use a web view only for genuinely web-native surfaces such as shader/WebGL previews, and isolate it behind a small adapter.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Porting the runtime doubles the migration scope | Port schema and one vertical runtime slice first, then migrate by bounded Dart modules. |
| Duplicate state between TypeScript and Dart | Keep one authoritative Dart service per migrated domain and use comparison tooling during transition. |
| Plugin UI migration expands without a boundary | Start with capability manifests and generic plugin pages. |
| Graph editor parity takes too long | Migrate low-risk workflows first and preserve Vue as fallback until graph editing is proven. |
| Desktop packaging or auto-update regressions | Add packaged Windows smoke tests before cutover. |
| Flutter web views weaken accessibility or performance | Limit web views to isolated web-native previews and measure them. |

## Initial Milestone

The first implementation milestone is the architecture spike, not a full Flutter rewrite:

1. Create the Flutter Windows package and Dart package boundaries.
2. Port settings, health, JSON persistence, and one resource model.
3. Display loading, ready, error, and save states from Dart services.
4. Test startup, persistence compatibility, validation failure, and clean shutdown.

This milestone decides whether the final host model is viable and gives the migration a measurable technical foundation.

## Definition of Done

- Flutter is the default Windows desktop UI.
- Core runtime and plugin behavior remains covered by existing TypeScript tests.
- Flutter has widget, integration, and packaged smoke coverage for critical workflows.
- Profiles, automations, queues, overlays, integrations, updates, and settings preserve their existing contracts.
- Existing user data opens without manual conversion beyond the current schema migration rules.
- The Vue renderer and temporary compatibility code are removed or explicitly retained only for documented web-native surfaces.
