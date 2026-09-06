# Product parity closure matrix

This inventory compares the Flutter replacement candidate with the frozen
`main` reference at `890ee2c9cc0522f2d8c747612920c6d12a1cb716`.

The generated contract report is `docs/parity.json`, based on
`parity-reference/main-2026-09-05`. It currently reports 26 `improved` and 6
`equivalent` plugin entries, with no missing contract IDs.

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
| Profiles | `ProfileEditor.vue`, `TriggerEdit.vue` | Profile workspace and profile runtime | equivalent | End-to-end lifecycle suite |
| Stream plans | stream-plan editor and resources | Stream Plan resource/editor/runtime surfaces | improved | Full-screen visual comparison |
| Integrations | plugin details/settings pages | Typed Dart plugin registry, workspaces, health and settings | improved | Full-screen visual comparison |
| Resources | resource store and resource editors | Resource repositories, typed editors, resource workspaces | improved | Full-screen visual comparison |
| Overlays | Vue browser-source overlay and editor | Flutter resource configuration, Shader Graph editor/compiler, plus browser overlay package | improved | Overlay visual/protocol comparison in OBS |
| Shader Graph | `shader-graph/shader-nodes.ts`, `shader-graph-state.ts`, `ShaderGraphEditor.vue` | Flutter `shader_graph_model`, `shader_graph_compiler`, `shader_graph_editor` using `sai_nodes` | improved | Compare compiled shaders and final OBS visuals |
| Variables | variable nodes and viewer data | Persistent variable resources and viewer-variable workspace | improved | Runtime fixtures |
| Queues | queue page and dashboard queue widgets | Queue workspace, queue manager and graph actions | improved | Runtime fixtures and E2E flow |
| Logs and diagnostics | integration feedback and update/status surfaces | Structured logs and diagnostics workspace | equivalent | Failure-injection E2E suite |
| Remote and Satellite | standalone satellite plus dashboard protocol | Remote host/client and versioned satellite protocol | equivalent | Resolved by `docs/architecture/adr-001-remote-agent.md` |
| Updater | update page/dialog and release metadata | Update check, artifact and install services | partial | Signed installed Windows upgrade/rollback proof |
| Data compatibility | `main` contains older document shapes | Strict V2 loader by explicit product decision | intentionally_removed | Older-shape conversion and automatic backup are out of scope |
| External plugin templates | `plugin-template` and `plugin-native-template` | No third-party in-process loader | intentionally_removed | Resolved in `docs/architecture/adr-003-external-plugins.md` |
| Media library | recursive media browser and import behavior | `MediaCatalogService`, SQLite `MediaIndexStore`, Quick/Full scan actions, debounced watcher and Media workspace | improved | Extended long-library correctness/performance corpus and full-screen comparison |
| Browser-only rendering | OBS HTML/WebGL runtime | `packages/showrunner-obs-overlay` remains browser-based | not_applicable | Protocol and browser build gates |

## Current closure order

1. Capture the frozen `main` screens and run the new controlled PNG comparison
   for every parity-critical workspace.
2. Expand document/runtime end-to-end coverage with close-flow and
   failure-injection scenarios around the existing fixtures.
3. Keep the media scanner within its persistent filesystem-index contract and
   extend the long-library correctness/performance corpus as needed.
4. Harden graph-editor stress behavior and close the remaining packaged
   updater proof.

The `partial` entries are the remaining product-proof or infrastructure work.
They are not missing plugin contracts.
