# Product parity closure matrix

This inventory compares the Flutter replacement candidate with the frozen
`main` reference at `890ee2c9cc0522f2d8c747612920c6d12a1cb716`.

The generated contract report is `docs/parity.json`, based on
`parity-reference/main-2026-09-05`. It currently reports 25 `improved` and 7
`equivalent` plugin entries, with no missing contract IDs.
The broader product-surface manifest is `docs/product-surface.json`
and is checked by `corepack yarn parity:product`.

Status values:

- `equivalent`: the supported workflow is represented and covered;
- `improved`: Flutter provides the reference workflow plus additional typed or
  observable behavior;
- `partial`: the main workflow exists, but a release or visual proof is still
  missing;
- `intentionally_removed`: explicitly outside the Flutter replacement scope;
- `not_applicable`: the reference surface is not a desktop Flutter concern.

| Product surface | `main` reference | Flutter implementation | Status | Remaining proof or decision |
| --- | --- | --- | --- | --- |
| Application shell | `SystemBar.vue`, `ProjectView.vue`, `App.vue` | `ShowRunnerShell`, `SystemBar`, `ProjectPanel` | equivalent | Full-screen visual comparison |
| Commands and menus | `SystemBar.vue`, command handlers | `AppCommandRegistry`, keyboard routing, menu actions | equivalent | Full-screen visual comparison |
| Documents | resource/document stores and save dialogs | `WorkspaceDocumentManager`, automation/profile document managers | equivalent | End-to-end lifecycle suite |
| Project navigation | project groups and resource entries | Flutter project panel and workspace routing | equivalent | Full-screen visual comparison |
| Automation editor | `NodeAutomationEdit.vue` and graph helpers | Flutter graph editor, runtime, debugger, data wires, subgraphs | improved | Stress benchmark and full-screen visual comparison |
| Timeline editor | README claims a Timeline mode; no Timeline editor source exists in the renderer | No separate Timeline surface | intentionally_removed | Resolved in `docs/architecture/adr-002-timeline.md` |
| Profiles | `ProfileEditor.vue`, `TriggerEdit.vue` | Profile workspace and profile runtime | equivalent | Activation conditions and inline, reorderable trigger/automation cards are implemented; remaining profile-shell visual alignment needs review |
| Stream plans | stream-plan editor and resources | Inline Stream Plan document tabs, resource repository and runtime | improved | Further visual alignment against the frozen reference |
| Integrations | plugin details/settings pages | Typed Dart plugin registry, workspaces, health and settings | improved | Full-screen visual comparison |
| Resources | resource store and resource editors | Resource repositories, typed editors, resource workspaces | improved | Full-screen visual comparison |
| Overlays | Vue browser-source overlay and editor | Flutter resource configuration, Shader Graph editor/compiler, plus browser overlay package | improved | Overlay visual/protocol comparison in OBS |
| Shader Graph | `shader-graph/shader-nodes.ts`, `shader-graph-state.ts`, `ShaderGraphEditor.vue` | Flutter `shader_graph_model`, `shader_graph_compiler`, `shader_graph_editor` using `sai_nodes` | improved | Compare compiled shaders and final OBS visuals |
| Variables | variable nodes and viewer data | Persistent variable resources and viewer-variable workspace | improved | Runtime fixtures |
| Queues | queue page and dashboard queue widgets | Queue workspace, queue manager and graph actions | improved | Runtime fixtures and E2E flow |
| Logs and diagnostics | integration feedback and update/status surfaces | Structured logs and diagnostics workspace | equivalent | Failure-injection E2E suite |
| Remote and Satellite | standalone satellite plus dashboard protocol | Remote host/client and versioned satellite protocol | equivalent | Resolved by `docs/architecture/adr-001-remote-agent.md` |
| Updater | update page/dialog and release metadata | Update check, artifact and install services | partial | Signed installed Windows upgrade/rollback proof |
| Older document shapes | `main` contains multiple document shapes | Strict V2 loader by explicit product decision | intentionally_removed | Only the canonical V2 document contract is supported |
| External plugin templates | `plugin-template` and `plugin-native-template` | No third-party in-process loader | intentionally_removed | Resolved in `docs/architecture/adr-003-external-plugins.md` |
| Persistent Media Library | No target product surface | No persistent catalog, scanner, database, watcher, or workspace; local file selection remains available for sound and overlay resources | intentionally_removed | Not part of the CastMate/ShowRunner product surface |
| Browser-only rendering | OBS HTML/WebGL runtime | `packages/showrunner-obs-overlay` remains browser-based | not_applicable | Protocol and browser build gates |

## Current closure order

1. Close the remaining visual differences intentionally: either align a
   screen to the frozen reference or record the product decision behind an
   intentional Flutter improvement/removal.
2. Capture the environment-dependent release evidence: a trusted signed
   Windows install upgrade/rollback, long-running Remote/plugin soak, and
   live OBS comparisons for browser overlays and compiled shaders.

The graph stress benchmarks, runtime parity fixtures, document/runtime
end-to-end coverage, and automated updater replacement/rollback proof are now
checked in. The `partial` entry is therefore release/visual proof work, not a
missing plugin contract or unimplemented graph pipeline.

## Current screenshot evidence

The visual catalog now contains 13 paired captures at 1440 x 900. Running
`corepack yarn visual:compare:catalog` on 2026-09-23 with a zero per-channel
threshold measured these raw pixel differences:

| Screen | Different pixels |
| --- | ---: |
| App empty | 72.61% |
| Settings | 53.48% |
| Updater | 73.59% |
| Integrations | 78.84% |
| Twitch | 63.29% |
| YouTube | 72.38% |
| Queues | 80.01% |
| Variables | 71.73% |
| Viewer Variables | 80.54% |
| Automation editor | 68.90% |
| Profile editor | 74.26% |
| Stream Plan editor | 70.30% |
| Overlay editor | 78.34% |

The frozen Electron reference's `FlexScroller` leaves `.scroller-outer` at zero
height in the offscreen capture window, hiding the Profile and Stream Plan
document contents. The reference capture harness sets that element to the
document pane's available height after opening those documents; this is a
capture-only layout correction, not a source change to the frozen reference.

The Stream Plan editor now opens as a named workspace document rather than a
modal. Editing updates the tab title and dirty marker, Save persists the plan
and refreshes the active runtime, and Save All/close/exit use that same
document state. The updated 70.30% raw screenshot difference is still not a
passing parity result; detailed layout alignment remains open.

The Profile editor now uses the reference-style Boolean condition builder
(nested All/Any groups, value comparisons, state/value operands, and ordering)
instead of exposing the serialized condition JSON. Empty groups evaluate as
Always On, matching the Electron editor/runtime semantics. The refreshed
profile screenshot is still a large raw pixel difference because the overall
Flutter workspace layout and trigger editor remain different.

These figures come from the checked-in PNGs, not from an assertion that the
screens are visually equivalent. The current CI step checks that the pairs can
be compared and reports the differences; it has no acceptance threshold, so a
green catalog step does not mean visual parity passed. Several captures also
predate explicit product decisions such as the native Windows title bar,
tabbed Settings, and removal of Media Library. Refresh the reference fixtures
against the accepted product decisions, review each remaining difference, and
then set per-screen tolerances before calling visual parity complete. Matching
captures now exist for Profiles, Stream Plans, and the Overlay editor; several
plugin settings pages still need reference/Flutter screenshot pairs.
