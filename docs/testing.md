# Testing

Use Flutter 3.47.7 / Dart 3.13.5, Node 22 and Yarn 4.1.0. Install the committed
lockfiles. Tests and smokes must use temporary application data; live settings,
OBS profiles and credentials are never disposable fixtures.

## Baseline and behavior contracts

Overlay protocol fixtures are shared verbatim by Dart
`test/plugins/overlays/overlay_protocol_test.dart` and TypeScript
`tools/overlay_registry/protocol.test.mjs`. Loopback peer/bridge tests cover
pending-call limits and expiry, duplicate IDs, late responses/results, join limits
and disposal during resource lookup. HTTP fixtures cover concurrent starts,
stop during startup and continuation after handler removal, shutdown or timeout.
Browser transport fixtures cover handshake deadlines, secure WebSocket selection,
binary/malformed/oversized frames, send-buffer saturation and timer cleanup.
These fixtures prove transport behavior, not LAN authentication, private-field
projection, live OBS rendering or GPU compatibility.

`node tools/overlay_registry/transport-browser-smoke.mjs` (after `overlay:build`)
launches an isolated Dart bridge and real Chromium. It proves fragment-to-session
bootstrap, an HttpOnly cookie, same-overlay config, foreign-overlay denial,
versioned WebSocket config/RPC delivery and shutdown. The host uses synthetic data
and an ephemeral secret; raw manifests and reports stay under `.tmp/protocols`.
The token persistence fixture verifies concurrent owners retain one encrypted-store
secret, public settings exclude it, and malformed stored secrets are preserved.
This is loopback evidence, not live OBS or untrusted-network/cloud identity proof.

The reference for the baseline/security work is commit `872f3b2f1` (the integrated
chat branch). It was captured with a clean working tree on Windows 11 Pro x64,
build 26200, Flutter 3.47.7 / Dart 3.13.5, Node 22.23.2 and Yarn 4.1.0. Both
committed lockfiles were unchanged. The source-equivalent PR CI passed 704 Flutter
tests (10 opt-in skips), 97 native scenarios (one audio skip), 128 JavaScript tests,
reviewed visual comparisons and Chromium. This is CI evidence, not a new local run.

Regenerate the lexical inventory with
`node tools/audit-baseline.mjs .tmp/audit-global/inventory.json`. It records HEAD,
status, environment, lockfile SHA-256 values, source/test domains, largest files,
registration/listener/timer/server candidates and import cycles. The clean
reference contained 668 source files: 572 Dart, 85 TypeScript, one JavaScript build
helper and nine native C++/header files plus one TypeScript build configuration.
There were 45 `part` declarations owned by seven libraries. The import scan found one four-file schema
cycle; it collapses Dart parts and excludes unresolved package aliases and native
includes. Type-only import cycles do not prove runtime initialization failures.
Static sites include tests/generated code and do not count live handles.
In particular, module implementation sites are not the registered plugin count.
Contract inventories remain the authority for the 34 plugins, 174 actions and
60 triggers. Large editors are inventory findings, not grounds for a rewrite.

The initial local focused baseline passed 48 tests in 4.50 seconds, including
overlay transport, registry lifecycle, persistence, secret projection, HTTP,
chat dock and remote fixtures. Raw reference, inventory, before/after security
reproducers and subsequent check outputs belong in ignored `.tmp/audit-global/`.
No permanent dated audit logs are needed. Timings include runner startup and
are not interchangeable with nightly benchmark medians/p95 or GPU frame rates.

| Contract surface | Existing characterization fixtures | Remaining proof boundary |
| --- | --- | --- |
| Shell startup, wizard, dirty/save/cancel, restart and tray/close | `test/app/app_lifecycle_coordinator_test.dart`, `integration_test/application/first_run_setup_test.dart`, `document_lifecycle_test.dart`, `document_edit_save_close_test.dart` | 1024x640 wizard is covered by the native fixture; OS tray interaction remains a manual boundary |
| Immutable graph authoring, history, subgraphs, shader semantics | `test/graph/`, `test/plugins/overlays/shader_graph_controller_test.dart`, `integration_test/visual/editor_workflows_test.dart`, `shader_workflows_test.dart` | Frozen Electron catalog remains diagnostic |
| Execution equivalence, branches/loops, cancellation, nested errors and traces | `test/graph/automation_execution_test.dart`, `test/runtime/execution_trace_test.dart`, `integration_test/runtime/runtime_workflows_test.dart` | External action side effects require live credentials |
| Queues, profiles and serial Stream Plan transitions | `test/runtime/action_queue_test.dart`, `profile_runtime_test.dart`, `test/plugins/stream_plans/stream_plan_test.dart`, `integration_test/resources/queue_lifecycle_test.dart` | Real provider delivery remains opt-in |
| Plugin availability, start/stop and reconnect | `test/plugins/registry/plugin_registry_test.dart`, `integration_test/plugins/provider_lifecycle_test.dart` | Enable/disable gates invocation; it does not promise worker stop/start on each toggle |
| Unsupported/invalid data, atomic writes, secret separation, junctions | `test/persistence/persistence_safety_test.dart`, `atomic_file_test.dart`, `secret_settings_store_test.dart` | Deterministic abrupt process exit is covered at journal checkpoints; hardware power loss and hostile ancestor replacement during syscalls remain outside the proof |
| Overlay/remote assets, RPC, ACL, shader rendering | `test/plugins/overlays/websocket_bridge_test.dart`, `test/plugins/remote/dashboard_host_test.dart`, `tools/overlay_registry/browser-smoke.mjs` | See architecture trust review for unresolved LAN capabilities and quotas |
| Chat priority/cooldowns/counters, identity scoping and private/public isolation | `test/features/chat/`, `integration_test/application/chat_workspaces_test.dart` | Twitch whispers and YouTube privileges still require account validation |
| Unsigned packaging, startup and updater rollback | `test/features/support/update_install_service_test.dart`, `scripts/smoke-flutter-windows.ps1`, release dry-run | Publishing remains a separate manually authorized operation |

Keep this matrix tied to executable fixtures. Add a missing behavior test before
changing its implementation; do not duplicate an equivalent suite or mark an
untested access path as a confirmed vulnerability. Baseline phase completion also
requires closing the open items in the architecture trust review.

Validation of the initial baseline/security changes, using the pinned environment
above (wall-clock times include process startup):

| Local gate | Actual result | Elapsed |
| --- | --- | --- |
| `ci-check.ps1 -Stage All` | Format/analyze, docs/version/registry/typechecks and inventories passed; 712 Flutter tests passed, 10 opt-in skips; 128 JavaScript tests passed | 69.61 s |
| `ci-check.ps1 -Stage Parity -Integration -Visual` in isolated native checkout | 97 passed, one existing audio skip; both reviewed inspector regions had zero differing pixels; frozen Electron catalog remains diagnostic with historical differences | 238.49 s |
| Chromium overlay/dock smoke | DOM/WebGL compile/render, update/removal/shutdown, chat history, keyboard completion, HTML safety and composer passed | 6.80 s |
| Incremental Windows lifecycle rebuild after adding the LAN machine-hostname allowance | One native document lifecycle test passed; IP/localhost/machine-name and denied-authority cases also passed in focused HTTP tests | 21.69 s |

Before the fixes, three HTTP boundary probes failed with 204 instead of 403;
malformed overlay JSON produced an unhandled exception and a peer timeout. The
first full check also caught a braces lint in a newly added test; it was corrected
before the successful run above. No assertion, visual threshold, reference capture
or SDK/lockfile requirement was relaxed. No live credentials, OBS profile or
production resources were used. This validation does not close the remaining LAN
capability, quota, secret-projection and manual/device items in the trust review.

## Application composition and lifecycle contracts

The composition work starts from baseline/security commit `0e29f7064`. Platform
bootstrap remains in `main.dart`; application models have explicit owners described
in the [ownership matrix](architecture.md#dependency-and-lifecycle-ownership).
The graph authoring model, command history and stored document formats are unchanged.
No new state framework, dynamic service locator or external-plugin ABI is introduced.

| Contract | Evidence |
| --- | --- |
| Validated immutable settings snapshots, safe unknown-ID omission, ordered early navigation, coalesced writes and failure recovery | `test/app/workspace_navigation_controller_test.dart`; atomic settings patches preserve other preferences |
| Save All, save/discard/cancel, revision and document-identity checks, pending modal cancellation | `test/app/document_session_coordinator_test.dart`; real repository round trips plus injected blocked writers |
| Root owner restoration and awaited, repeatable shutdown; isolated Stream Plan state | `test/app/application_controller_test.dart`, `showrunner_services_test.dart` |
| Dependency order, shutdown during blocked start, failed-start cleanup and continued cleanup after failures | `test/app/application_runtime_test.dart`, service tests and `test/plugins/registry/plugin_registry_test.dart`; failed start releases a real loopback listener |
| Active action cancellation, retained pending queue work and no live gap timer after close | `test/runtime/automation_queue_manager_test.dart`; widget binding rejects leaked timers |
| Variable writes finish before registry/notifier shutdown, late edits are rejected | `test/plugins/variables/variable_runtime_test.dart` holds a real resource transaction lock and verifies both persisted value and registry state |
| Event writes finish before the event hub closes | `test/persistence/viewer_data_sync_test.dart` blocks a real viewer JSON atomic write |
| Tray initialization/close race and exactly one icon destruction | `test/app/showrunner_tray_test.dart` mocks the platform method channel; this is not a claim about manual OS tray interaction |
| Cancelled document/profile guards and hide-to-tray keep services alive; duplicate close is guarded; timeout leaves the window open and teardown running | `test/app/window_close_coordinator_test.dart` |
| Command routing follows the visible workspace and runtime availability | `test/app/app_command_registrar_test.dart`; the hidden-graph run probe failed against the original registrar before the guard was added |
| All stable workspace IDs and resource document builders remain registered | `test/app/workspace_registry_test.dart`; product evidence points to the feature-owned builder files |

Native application fixtures adopt an explicit `ApplicationController` and register
its awaited shutdown after the directory-cleanup callback, so teardown's reverse
order finishes owned I/O before fixture deletion. Restart fixtures unmount and await that owner before rebuilding;
navigation assertions explicitly flush debounced writes before reading settings.
Fixed sleeps and retrying directory deletion do not establish lifecycle completion.

Native acceptance retains `creation_lifecycle`, `document_edit_save_close`, both
first-run fixtures (including 1024x640), resource/queue/profile/provider workflows,
chat, shader/editor workflows and the complete workspace catalog. The catalog
continues to scroll the lazy sidebar both down and back up before selection.

The capture contract remains Flutter 3.47.7 / Dart 3.13.5, 1440x900 at DPR 1 with
the existing reviewed inspector regions and frozen Electron references. There is
no intended layout/font change and no baseline replacement. Raw command output,
source-equivalence proof, the original hidden-run reproducer and captures live
in ignored `.tmp/app-composition` and the isolated native checkout. Testing never
uses the user's OBS profiles, credentials or production data.

Final composition verification used the pinned SDK above and unchanged lockfiles.
The isolated native checkout matched all 769 committed product/test source files
under `packages`, `libs` and `plugins` after normalizing line endings. Graph and
inspector captures were inspected; both reviewed inspector regions had zero
differing pixels. The catalog passed its existing gate; historical Electron
pixel differences remain diagnostic, not a full pixel-parity claim.

| Local gate | Actual result | Elapsed |
| --- | --- | --- |
| `ci-check.ps1 -Stage All` | Format/analyze, docs/version/generated-registry/typechecks and inventories passed; 743 Flutter tests passed, 10 opt-in skips; 128 JavaScript tests passed | 82.00 s |
| `ci-check.ps1 -Stage Parity -Integration -Visual` in isolated native checkout | 97 passed, one existing opt-in audio skip; catalog passed; zero differing pixels in both reviewed regions | 260.76 s |
| Chromium overlay/dock smoke | DOM/WebGL rendering/update/removal/shutdown and chat history, HTML safety, filters, composer and keyboard completion passed | approximately 6.8 s |

No assertion, SDK requirement, screenshot baseline or comparison threshold was
weakened. These results validate the composition/lifecycle work; the remaining
baseline network-security and live-account/device proof boundaries remain as
recorded above and in the architecture trust review.

## Plugin composition and provider lifecycle contracts

Phase 02 starts from integrated main `3a4051905`. Generated inventories before
and after the work are identical: 34 plugins, 174 actions, 61 triggers, 57 states,
20 resource types and 65 settings, including their UI metadata. Canonical resource
declarations now live with providers; Flutter editor ownership is preflighted.
Saved graph IDs/payloads and generated overlay contracts are unchanged.

| Behavior | Executable proof |
| --- | --- |
| Atomic pack registration, factory identity/version, required/optional dependency order, cycles and resource/editor ownership | `test/plugins/registry/plugin_registration_test.dart`, `plugin_registry_test.dart` |
| Persisted enable transactions, concurrent toggles, rollback, skipped/failed startup and reverse teardown | `test/plugins/registry/plugin_lifecycle_test.dart`; plugin visibility/settings race fixtures |
| Distinct disabled, missing-configuration, disconnected and healthy states; bounded/stale health results | `test/plugins/registry/plugin_health_test.dart` |
| No Flutter screens in manifests/runtime; provider-owned factories and static composition | `test/plugins/registry/plugin_architecture_test.dart` |
| EventSub keepalive/reconnect/subscription order, parsing and private whisper isolation; YouTube polling/cursor/late-response behavior | `test/plugins/twitch/event_worker_test.dart`, `test/plugins/youtube/live_chat_worker_test.dart` |
| Disconnect during settings/socket/discovery work, independent platforms, concurrent selection and fresh credentials | `test/plugins/runtime/provider_runtime_lifecycle_test.dart`; existing unified-chat active-worker precedence fixture |
| Immutable/redacted envelopes, private/public isolation, bounded paused queues, atomic publication and explicit overload/restart | `test/services/plugin_event_hub_test.dart`; Twitch/YouTube worker overload fixtures |
| HTTP body/deadline bounds, non-retried writes, physical HTTP/TCP/UDP cancellation, borrowed client ownership and token-write completion | `test/plugins/runtime/provider_operation_policy_test.dart`; Kasa oversized-header fixture |
| Audio/TTS ownership, anonymous playback abort, awaited cleanup, late-start rejection and action cancellation | `test/plugins/sound/sound_lifecycle_test.dart`, `test/runtime/cancellation_test.dart`; no audible output |
| Shared OBS transport shutdown and late connection guards; active-stream automation toggle policy with retained BLE transport | OBS router fixtures and `integration_test/plugins/provider_lifecycle_test.dart`, `heart_rate_lifecycle_test.dart` |

The final lexical inventory contains 766 source/test files versus 697 initially,
with 42 part declarations versus 44. The existing four-file TypeScript schema
cycle is unchanged; no new import cycle is reported. These are lexical counts,
not counts of live handles. Both dependency lockfile hashes are unchanged.
Raw before/after inventories, generated contract comparisons and check outputs
remain in ignored `.tmp/plugin-provider/`.

Final checks use Windows 11 x64, Flutter 3.47.7 / Dart 3.13.5, Node 22.23.2 and
Yarn 4.1.0. The isolated native checkout is verified against 974 tracked files
after line-ending normalization; its build/storage/captures remain separate from
the working checkout and user data. There is no intended layout/font change:
1440x900 at DPR 1, the existing reviewed inspector regions, frozen Electron
references and comparison thresholds remain unchanged.

| Local gate | Actual result |
| --- | --- |
| `ci-check.ps1 -Stage All` | Formatting, analysis, docs/version/generated-registry/typechecks and parity pass; 809 Flutter tests pass with 10 opt-in skips; 132 JavaScript tests pass |
| `ci-check.ps1 -Stage Parity -Integration -Visual` in isolated checkout | 97 native scenarios pass, one opt-in audio skip; catalog gate passes and both reviewed inspector regions have zero differing pixels |
| Chromium overlay/dock smoke | DOM/WebGL render/update/removal/shutdown, chat history, HTML safety, filters, composer and completion pass |
| Chromium shader catalog | All 89 exported shaders link/render without reported errors |

Graph, diagnostics and inspector captures are inspected under this contract;
historical Electron catalog differences remain diagnostic. Simulated providers,
loopback HTTP/TCP/UDP and injected BLE/audio services establish lifecycle behavior,
not live Twitch/YouTube privileges, OBS/CEF delivery, hardware compatibility or
subjective audio quality. No production profiles, credentials or live providers
are used. Baseline network-security items remain tracked in the trust review.

## Graph invocation, queue and trace contracts

Phase 03 starts from integrated main `ec1435276`. Authoring documents remain immutable, and the compiled VM remains the production engine with the separate interpreter as its oracle. The dispatch inventory and exact queue/direct policies live in [architecture](architecture.md#authoring-and-execution).

| Behavior | Executable proof |
| --- | --- |
| Typed direct results versus accepted queue receipts, immutable inputs, original errors and preflight validation | `test/runtime/automation_invocation_service_test.dart`; editor/profile/plan/command/quick-action fixtures |
| Reserved drain ownership, concurrent waiters, exact snapshot/replay and recovery after load failure | `test/runtime/automation_queue_manager_test.dart` |
| Timeout cancellation with awaited physical cleanup, no following-action overlap, owned gap timers and shutdown | Queue manager and `test/runtime/action_queue_test.dart` |
| Session-owned subscriptions/direct work, concurrent activation/replacement, awaited close and retained background failure | `test/runtime/profile_lifecycle_test.dart`, `profile_runtime_test.dart` |
| Plan transition cancellation, rejected waiting navigation, failed activation state, reverse cleanup and preserved cleanup failures | `test/plugins/stream_plans/stream_plan_lifecycle_test.dart`, existing plan manifest fixtures |
| Bounded nodes/edges/events/invocation counters, truncation, paused observers and frame-coalesced visuals without dirty authoring | `test/runtime/execution_trace_test.dart`, `test/graph/execution_visual_adapter_test.dart`, `integration_test/visual/editor_workflows_test.dart` |
| Credentials/private/viewer values omitted by default; safe opt-in fields cannot bypass deny rules; raw error text/stacks omitted | `test/runtime/execution_trace_test.dart` |
| Deterministic compiler symbols, operand validation before actions, invalid documents/contracts, guarded cycles and independent execution parity | `test/graph/compiler_helpers_test.dart`, `compiled_interpreter_differential_test.dart`, existing execution/edge suites |
| Semantic cache invalidation, presentation reuse, bounded identity memo/LRU, exact entry choices and fresh contexts | `test/graph/graph_program_cache_test.dart`, existing execution parity fixtures |

Final local gates use Windows 11 x64, Flutter 3.47.7 / Dart 3.13.5, Node 22.23.2 and Yarn 4.1.0. `ci-check.ps1 -Stage All` passes docs/version/release-check/generated registry/build/typechecks, 132 JavaScript tests, parity and the Flutter suite. After the final invalid-input fixtures, `-Stage Flutter` passes formatting, fatal-info analysis and **951 tests with 10 opt-in skips**.

The isolated `-Stage Parity -Integration -Visual` gate passes **98 native scenarios with one opt-in audio skip**, including the real production composition's graph, nested subgraph, queue and profile flows, plan transitions, inline cancellation and editor workflows. Catalog comparison has no gate failures; both reviewed inspector regions have **zero differing pixels**. Graph, diagnostics and inspector captures were inspected at 1440x900/DPR 1. Existing frozen Electron references, reviewed Flutter baselines and thresholds are unchanged. Historical Electron catalog differences remain diagnostic, not a claim of pixel equality across runtimes.

The isolated checkout was synchronized and checked against 1,003 tracked files after newline normalization. The last added cases change unit tests only; native production sources match the final product. Public exported contracts remain identical to main: 34 plugins, 174 actions, 61 triggers, 57 states, 20 resource types and 65 settings. Both lockfiles are unchanged. The lexical inventory contains 795 source/test files and 42 part declarations, with the same existing TypeScript schema cycle and no new import cycle.

A separate temporary comparison checked all instruction operands, edge IDs, slot names and compiled subgraph bindings on 100 seeded graphs against the compiler before extraction: all match. Authoring benchmarks pass load/move/round-trip and undo/redo at 100 through 5,000 nodes. Runtime distributions and allocation-sampling limits are recorded in the benchmark contract below. Ignored logs, reports, comparison probes and captures remain under `.tmp/graph-runtime` and the isolated checkout; no permanent dated QA log is added.

These results use synthetic providers, injected capabilities and loopback services. They establish dispatch, lifecycle, persistence and visual contracts, not live provider permissions or external side-effect rollback. Timeout/close can still wait for a non-cooperative plugin to finish its owned cleanup. Accepted queue work remains queue-owned when a profile session stops. No live accounts, credentials, user OBS profiles or production resources are modified. No new browser shader claim is made: this phase changes no shader/browser rendering code.


## Persistence, resource editors and secrets

Phase 04 starts from integrated main `a4278743d`. The storage catalog covers all 20
canonical resource families plus automations, profiles, queues, viewer data, plugin
settings and chat state. Current JSON/YAML formats and resource identities remain
unchanged. There is no migration decoder or automatic repair/reset of unsupported
files. The public contract snapshot is identical before/after: 34 plugins, 174
actions, 61 triggers, 57 states, 20 resources and 65 settings. Both committed
lockfiles have unchanged hashes. Source inventory falls from 42 to 27 `part` sites;
all 15 resource editor parts become ordinary provider-owned libraries. The one
previously recorded TypeScript schema import cycle remains unrelated to this work.

| Storage/editor contract | Executable evidence |
| --- | --- |
| Coherent public/state/secret recovery; failed deletes/cleanup; conflicting external bytes preserved | `test/persistence/file_transaction_test.dart`, `resource_recovery_test.dart`, `plugin_settings_store_test.dart`; faults before/after each publication, ciphertext-only secret journal payloads and independent process crash/lock fixtures |
| Strict current formats, optimistic editor revisions, immutable accepted inputs and anchored project factories | `authoring_store_contract_test.dart`, `resource_revision_test.dart`, `project_storage_test.dart`, `test/app/document_session_coordinator_test.dart` |
| Semantic resource fidelity | `resource_codec_contract_test.dart`: all 20 families in both JSON and YAML, unknown fields/state retained, malformed complex collections rejected without rewriting source, unbounded queue timeout and Stream Plan segment fields retained |
| Provider-qualified viewer semantics across adapters | `viewer_store_contract_test.dart`: file/in-memory defaults, scoping, groups, import, pagination, concurrent increments and stale definition edits |
| Native DPAPI and unavailable secrets | `secret_settings_store_test.dart`, `persistence_safety_test.dart`: real Windows encrypt/decrypt plus deterministic bad-cipher/read/write probes; declared fields merge, unrecognized encrypted fields remain opaque |
| Windows containment and YAML safety | `persistence_safety_test.dart`, `project_storage_test.dart`: traversal, directory collisions, trailing separators, junction/dangling link containment, recursive aliases and non-string YAML keys |
| Catalog ownership and diagnostics | `test/app/project_panel_controller_test.dart`, `test/services/project_catalog_service_test.dart`, `test/plugins/resources/resource_workspace_diagnostics_test.dart`: cached queries, scoped invalidation, shutdown drains and payload-free failures alongside healthy entries |
| Draft/history retention and editor availability | `resource_editor_contribution_test.dart`, resource/overlay editor suites: disabled/unknown/malformed fallback, save failures retain drafts, disable/re-enable preserves mounted editor state; coordinator rejects unavailable-owner save/delete |
| Runtime state versus authoring | `test/plugins/variables/variable_runtime_test.dart`: ID/alias increments serialize; runtime patches preserve newer config and unrelated state, respect disabled persistence and do not recreate deleted resources |
| Native CRUD and restart | `integration_test/resources/resource_crud_test.dart`, `extended_editors_test.dart`, `resource_workspace_lifecycle_test.dart` and overlay fixtures; malformed resource remains visible beside healthy data across app restart without rewriting or showing parser source |

Local full validation uses Windows 11 x64 and the pinned SDK above. The complete
`ci-check.ps1 -Stage All` passes formatting, fatal-info analysis, 1,131 Flutter tests
with 10 intentionally opt-in live-provider skips, 133 overlay tests in 22 files,
typechecking/build/generated checks and product parity across 18 workspaces.
Native validation runs from a byte-equivalent isolated checkout under `.tmp`,
with no user profile/storage writes. The opt-in local audio probe requires
`SHOWRUNNER_LOCAL_AUDIO=1`; this phase does not claim live audio/device validation. Captures retain the existing 1440x900 logical
viewport at DPR 1. The editor extraction intends no layout/font changes; frozen
Electron references and regression thresholds are unchanged. The final
`-Stage Parity -Integration -Visual` gate passes 99 native scenarios with one
opt-in audio skip. Both reviewed inspector regions have zero differing pixels;
actual label/font captures were visually inspected. The historical Electron
catalog comparison has no gate failures and remains diagnostic rather than a
claim of full cross-runtime pixel equality. An initial restart-fixture navigation
assumption was corrected to exercise the actual unreadable project row and safe
diagnostic toast; the focused probe and subsequent complete suite both pass.

Fault injection proves recovery at controlled journal/member boundaries, including
an abrupt process exit; it is not hardware power-loss certification. Containment
uses pathname checks rather than kernel no-follow handles, so hostile ancestor
replacement during a syscall remains a documented limit. Repository readers
recover coherent generations; raw filesystem readers do not get a simultaneous
multi-file snapshot. Existing bounded external HTTP/protocol paths remain in
force; authorized local authoring files receive no arbitrary new size cap.
Live credentials, provider permissions, external side-effect rollback and production
OBS resources are outside these isolated proofs. Raw reports/captures stay in
ignored `.tmp/persistence-resources` and `.tmp/chat-qa`.

## Flutter UI layout and editor ownership

Phase 05 starts from integrated main `27d43fcdd` and covers overlay authoring,
responsive layout, structured inputs, automation/shader controls, provider/status
views, resource/profile forms, settings, variables, chat/commands and remote/support
ownership. Tests use borrowed fake services, isolated storage and loopback transports;
these are UI/lifecycle proofs rather than live account/device certification.
The initial overlay/exploratory/graph characterization passes 36 tests. Three
valid-resource lifecycle reproducers fail against the integrated page: identity
switching keeps the first document's inputs, delayed save completion publishes the
wrong resource, and save errors interpolate arbitrary exception payloads. They
pass with the controller owner. Earlier malformed test fixtures were corrected to
include the required size object before using their results as regression evidence.

| Contract | Evidence |
| --- | --- |
| Immutable snapshots, stable selection, equivalent commands stay clean, one undo step per gesture, unknown fields/state and ID-less shipped layers preserved | Eight `overlay_editor_controller_test.dart` fixtures |
| Resource switching, stale save completion, retained failed-save draft and keyboard undo/redo/save | Four `overlay_editor_lifecycle_test.dart` fixtures |
| Save/canvas reachability, panel/field retention and display scaling | Nine `overlay_editor_layout_test.dart` fixtures at 1024x640, 1280x720, 1440x900 and 1920x1080, each at DPR 1 and 1.5; Ctrl+I hide/reopen and resize retain the mounted editable state and saved content |
| Native compact layout and shortcuts | Additional `integration_test/visual/overlay_alignment_test.dart` scenario uses an actual 1024x640 Windows window, a 300-pixel app-sidebar allowance and Ctrl+I/Ctrl+S to save a retained inspector draft |

Presence characterization uses Flutter's test-only `debugOnRebuildDirtyWidget` hook,
restoring it at teardown: the old observer increases canvas builds from 2 to 3 on
one presence update; the scoped observer keeps the count at 2 while displaying
the new status. A separate UI reproducer proves an old reply cannot replace the
new document's subscriber count. Seven controller fixtures cover delayed reader
startup/replies, one pending poll, synchronous failures/retry, close drains,
foreign identities and already failed startup futures. No rebuild counters or
profiling hooks are included in product output.

OBS characterization uses only injected recording actions. The old create-dialog
probe writes the newly selected overlay after a resource switch; the guarded
owner rejects it before any provider write. A separate debug-only counter proves
connection refresh no longer rebuilds the canvas. Ten controller fixtures cover
captured dimensions/ports, immutable choices, A-to-B-to-A replies, replaced-service
errors, stale dialog/lookup admission, duplicate writes, pre-write inspection,
provider errors and borrowed-service shutdown. Four workspace fixtures also
exercise keyboard history target refresh and verify ordinary rebuilds issue no
additional OBS reads. No user OBS profile or portable scene is changed.

Preview probes reproduce cross-document dialog/controller notifications during build
and loss of additional nested configuration in the old implementation; both pass
with the owned form. Four workspace fixtures cover those cases, disabled/reopened
values and delayed inspector callbacks with a layer ID shared by two documents.
Style probes reproduce an edited numeric field retaining 12.5 after an external
restore to 4, and a font popover replacing an external 23.5 size with its old 65.
The current inputs accept external changes while preserving partial signed decimal
text/focus on model echoes. Tests distinguish absent, explicit-null and zero-width
optional effects; existing font-control assertions now also check removed stroke
and shadow remain absent in the saved document. The resource, input and automation
workspace characterization passes 137 tests after these changes.

Graph characterization uses 14 workspace fixtures: stale picker results, compact
inspector replacement, concurrent subgraph parameter changes, old run completion,
trace rebuild isolation, and four desktop sizes at DPR 1/1.5 with 150% text and long
subgraph names. The original 13 fail against the pre-extraction workspace: trace
publication increases workspace builds from 1 to 2, a replaced pick inserts into the new graph,
and long names overflow by thousands of pixels. Current fixtures pass without
changing authoring/history ownership or the generic canvas. Two schema-field tests
verify payload-free retry, no loader calls on ordinary rebuilds and rejection of
late options from a replaced loader. The existing six graph workspace workflows
remain intact, including Ctrl+F, inspector sheets, parameter validation and undo.

Shader ownership probes cover retained palette search, reset picker admission and
Ctrl+F without invalidating compiled output. The shader matrix tests four desktop
sizes at DPR 1/1.5 and 150% text; the focused shader suites pass 39 tests. Global
variable probes measure zero catalog reads/notifications for 30 value updates and
verify that viewer queries/forms retain their repository generation. Twitch message
publication leaves workspace build and health-read counters unchanged; dashboard
channel refresh leaves catalog/workspace builds unchanged, and named queue cards
show their own counters. Plugin/settings probes cover declared-settings-only reads,
strict numeric parsing, secret/unknown configuration redaction and delayed load
replacement in both plugin and preferences forms.

Auxiliary owner probes replace the project, selected profile or command manager
while a dialog remains open. The resource probe awaits the accepted operation
before reading storage: the previous implementation writes into the replacement
project; the current implementation writes neither project. A 30-message chat burst
changes search build counts from 1 to 31 before isolation and leaves them at 1 now.
Chat layout probes reserve 300 logical pixels for the application sidebar at all
four desktop sizes, DPR 1/1.5 and 150% text, with the send action hit-testable. Profile
controls are resized through the same eight size/DPI combinations with enlarged
text. A fixed-width condition dropdown and profile heading now adapt to scaling.
A layer popup opened before reordering deletes its original layer and restores the
expected order with undo. Graph diagnostic navigation opened for an old document
cannot select a same-ID node in its replacement (the old implementation does).
Remote discovery tests deliver a newer success before an older failure and verify
retained results, safe errors and no reads on ordinary rebuilds. Support diagnostics
perform one plugin-health read across three rebuilds and another only on explicit
refresh, while retaining provider retry counters without echoing private errors.

Fifteen existing inspector/canvas fixtures now explicitly request the reviewed
1440x900/DPR-1 standard viewport rather than relying on Flutter's implicit 800x600
surface. Their assertions remain intact; compact behavior has dedicated coverage
through the actual toggle flow. Splitter position and toolbar input state remain
mounted across size classes. Standard/wide layout keeps the existing 352-pixel
inspector, toolbar/footer spacing, crop contracts and thresholds. Compact layout
intentionally overlays the panel and scrolls a height-limited toolbar; it is not a
new docking system or a saved layout format.

Native Save All assertions wait for the requested document to become the active
editor before modifying it, verify that menu commands are enabled and dismissed,
and await the application's owned document writes through `flushShowRunnerTestApp`
until both tabs are clean before checking persisted graphs.
A frame-count loop is not a disk completion signal on hosted Windows runners.
An injected writer probe blocks each sequential save independently and verifies
that `flush()` remains pending until both complete, with both undo histories intact.

Combined validation uses Flutter 3.47.7 / Dart 3.13.5 on Windows:
`scripts/ci-check.ps1 -Stage All` passes formatting, fatal-info analysis,
generated/boundary/build checks, 1,240 Flutter tests (10 opt-in live skips),
133 overlay/tooling tests across 22 files and parity for 18 workspaces. The
matching application sources copied to ignored `.tmp/chat-qa` pass
`scripts/ci-check.ps1 -Stage Parity -Integration -Visual`: 100 native tests,
with one local-audio opt-in skip. The graph matrix was also rerun with both view
and MediaQuery DPR explicitly set; all 14 ownership/layout fixtures pass.

The intended UI changes are the compact overlay panel/scrolling toolbar, bounded
long subgraph labels, shader find/snapping controls, scale-aware profile headings
and condition controls, and explicit diagnostic health refresh. Existing reviewed
overlay label and font-popover regions retain the 1440x900/DPR-1 capture contract: label `(1088,210,352,345)` and
font `(780,340,660,430)`. Both current regions have zero differing pixels after
manual inspection of the full captures; channel threshold 3 and maximum 0.5%
remain unchanged. Frozen Flutter/Electron references are untouched. Workspace
catalog comparison reports no contract failures; its cross-runtime pixel deltas
remain diagnostic and do not establish whole-application visual equivalence.
Raw captures, comparisons and regression-before/after logs stay ignored under
`.tmp/ui-layout` and `.tmp/chat-qa`. These fixtures establish local UI behavior,
not live provider permissions, production OBS writes or audio-device validation.

## Local checks and CI

```powershell
./scripts/ci-check.ps1
./scripts/ci-check.ps1 -Integration -Visual
```

The default runs documentation/version checks, overlay tests/typechecking, browser
boundary verification, generated-registry checks, Flutter formatting/analysis/tests,
and contract/product inventories. Integration adds the native Windows lifecycle
suite; Visual captures isolated 1440x900 fixtures and runs catalog/regression checks.
Together, Integration and Visual capture during the same native run. The grouped
native entrypoint compiles once for all 22 fixture files; the fixture-inventory
test prevents new native scenarios being omitted. Individual files can still be
run directly, and the standalone capture command uses a smaller grouped entrypoint.
CI also builds Windows Debug/Release, tests signing helpers with isolated fixtures,
runs startup smokes, and exercises the production overlay in Chromium.

GitHub runs windows-build (production Debug/Release, startup and signing-helper
proofs) alongside windows-integration (analysis/unit tests, contracts, one native
suite, captured visual comparisons and Chromium). The required test-windows check
is an aggregate that runs even after a dependency failure and accepts only success
from both Windows jobs. The other required names remain scripts-ubuntu and
release-dry-run. No fixture, assertion, screenshot region or tolerance is dropped.
Native persistence fixtures wait for the editor saved state before reading disk:
fixed animation pumps cannot establish completion of sequential Save All writes.
Command dispatch fixtures await manager notifications after counter persistence
rather than assuming disk writes complete within a fixed sleep.

The previous sequential Windows job took 30m20s: native fixtures 13m, production
builds 5m38s, Flutter checks 3m07s, duplicate captures 1m38s and cold SDK-cache saving
2m32s. The grouped local native run passed 96 tests with one audio probe skipped
in 3m17s after a single 14s incremental compilation, with zero differing pixels in
both reviewed regions. Local timings are not a prediction for a hosted runner;
use GitHub job durations to judge CI improvement and distinguish warm/cold caches.

The release preview is read-only and does not require publishing credentials.
Manual Release reuses successful main-push CI only for the exact planned commit
with every gate completed successfully; otherwise it runs the reusable workflow.
Nightly adds repeated benchmark sampling. PRs target main,
and CI push checks run only on main to avoid duplicate migration-branch runs.

## Focused checks

```powershell
node .yarn/releases/yarn-4.1.0.cjs overlay:test
node .yarn/releases/yarn-4.1.0.cjs overlay:typecheck
node .yarn/releases/yarn-4.1.0.cjs overlay:build
node .yarn/releases/yarn-4.1.0.cjs overlay:browser-smoke
Push-Location packages/showrunner-flutter
flutter test
flutter analyze --fatal-infos
Pop-Location
```

The graph runtime has an interpreter oracle and compiled VM fixtures. Native tests
cover authoring, strict persistence, save/reopen, selection/focus, undo/clipboard,
profiles, queues, resources, remote/provider lifecycle and overlay/shader workflows.
The first-run shell test uses a 1024x640 viewport and scrolls provider controls
into view before asserting hit-testability and clicking. Keep this smaller-screen
coverage so hosted runners exercise the same scrollable setup as desktop users.
Do not treat test counts from retired implementations as current coverage; use the
current CI result. The last completed graph-cutover verification recorded 650
unit/widget passes with 7 opt-in probes skipped, all 21 native integration files,
and 89 actual WebGL shader compile/link/render fixtures. This is historical evidence,
not a promise that current changes have already passed.

Browser smokes launch an isolated Chromium profile and require a responsive CDP
version endpoint within the existing ten-second startup deadline. They accept
the debugging address announced on stderr as well as `DevToolsActivePort`, retain
bounded startup diagnostics and try the next installed Chrome/Edge binary only
when startup fails. `SHOWRUNNER_CHROMIUM_BINARY` selects one explicit executable.
DOM/WebGL/chat assertions run once after readiness; a failed assertion is never
retried on another browser. Launcher fixtures cover missing port files, early
exit, spawn errors, unresponsive endpoints and isolated-profile cleanup.

## Visual checks

Chat/Commands adds the native `application/chat_workspaces_test.dart` fixture:
create/edit/enable/delete, alias-to-queue execution, counters, shared provider
history, filters and reply selection. Its review captures use Flutter 3.47.7 /
Dart 3.13.5, 1440x900 at DPR 1, under
`packages/showrunner-flutter/.tmp/chat-ui/`. The added sidebar destinations and
new workspaces are intentional; captures were visually inspected. The catalog
fixture explicitly scrolls workspace/group labels into view before selecting
them, including lazy rows above a previously scrolled Tools section. Frozen Electron
references and existing Flutter regression baselines are unchanged.
The full chat validation passed `ci-check.ps1 -Integration -Visual`; both reviewed
Flutter inspector regions had zero differing pixels. A native shader workflow
initially lost a binding after rapid field changes; the fixture now settles each
edit and checks its document value before continuing. Both occurrences in the
grouped Windows suite passed with the final binding assertions intact.

Advanced command fixtures additionally cover Allow/Deny users/roles/groups,
fail-closed group lookup, named regex captures and a pathological expression that
times out while the UI heartbeat keeps running. Graph plugin fixtures exercise
filtered lifecycle triggers, enable/delete and independent counter/cooldown resets.
The targeted Windows Chat/Commands fixture passes with the expanded editor; its
captured command list was inspected. Twitch delete/clear events are tested with
channel scoping and whisper input is asserted absent from public history. These
are fixture proofs; live whisper scopes and privileges remain unverified.

Preferences fixtures verify strict version/limit validation, platform-scoped
ignore/highlight identities, bounded regex rules, hide-only versus command-block
behavior, authenticated dock updates and preservation of unsupported preferences.
The native fixture edits display/highlight settings; Chromium verifies font and
history-direction synchronization. Captures were inspected, including highlight
text contrast. The capture contract remains Windows, Flutter 3.47.7, 1440x900/DPR 1;
no frozen inspector/Electron references or comparison thresholds were changed.

Configured chat-action fixtures cover immutable definitions, scoped targets,
platform enforcement, expired/deleted targets and curated public event fields.
The service composition fixture runs a user shortcut through the real saved-graph
queue and verifies resolved viewer/message/argument values. The native fixture
creates and executes a global shortcut and displays a public follow event;
Chromium verifies global/message/event requests and escaped event text.

Rich-emote fixtures cover provider parsing, channel/platform scope, Twitch
fragments with punctuation, trusted HTTPS hosts, animation/static selection,
public-catalog caching and partial provider failure. The widget proof verifies
image semantics and disabled-animation text fallback. Chromium intercepts CDN
requests with a generated PNG and an empty 404, verifying actual image decoding,
failed-image fallback and rejection of a malicious image URL without live CDN I/O.

The Chromium overlay smoke proof also exercises the chat dock with isolated mock
HTTP APIs: two-provider history, text escaping, filters, routing, emoji and reply.
The browser and default fixtures make no live provider calls and do not verify
OBS/CEF itself. The separate public-emote opt-in checks current 7TV/BTTV/FFZ
global responses without OAuth, channel access or writes; all three passed.

See [the visual harness](../tools/visual_parity/README.md). The historical Electron
catalog is diagnostic; a green comparison does not establish pixel equivalence.
Selected Flutter baselines have explicit regions and a 0.5% differing-pixel limit
at channel threshold 3. Keep the threshold and frozen reference images intact.

### Reviewed baseline SDK transition

The reviewed baselines were originally committed in e64552bb1 when CI pinned
Flutter 3.44.0. The main-integration work pins all workflows to Flutter 3.47.7 /
Dart 3.13.5, matching the maintained local toolchain. Fresh isolated 1440x900
captures reproduce the prior label/font differences of 2.248024% / 0.885130%.
The pre-rewrite inspector had reproduced those same differences on this SDK;
this is not a newly introduced graph-editor layout change.

The two inspector crops were inspected side by side: text/font choices, alignment,
geometry, color inputs, stroke and shadow controls remain the intended UI. The
reviewed Flutter PNGs are refreshed for this supported SDK. No product widget,
frozen Electron image, comparison region, channel threshold or 0.5% tolerance is
changed. A second independent native capture passed with 0 differing pixels in both
regions at the unchanged channel threshold 3 and 0.5% limit. GitHub Windows
captures independently passed with 0 differing pixels in both regions. The full
21-file native suite also passed locally and on GitHub, with its opt-in audio
probe skipped. These results cover the pinned capture contract and SDK, rather
than establishing universal pixel equivalence across machines.

## Browser shaders and audio

Export fixtures from the Flutter shader tests with SHOWRUNNER_EXPORT_SHADER_FIXTURES=1,
then run `node tools/overlay_registry/shader-catalog-smoke.mjs` after overlay:build.
The browser test compiles and renders real WebGL output; it does not cover every GPU.
Local native audio tests are opt-in with SHOWRUNNER_LOCAL_AUDIO=1 and can use system
output. Simulated services and successful WAV generation are not subjective audio
quality validation.

## Benchmarks

Nightly runs tool/graph_benchmark_test.dart and tool/graph_execution_benchmark_test.dart
five times and summarizes median/p95 values with tools/benchmarks/summarize.mjs.
They verify history/serialization, compiler caching, loops and subgraphs as well as
timings. JIT wall-clock results are not GPU frame rates. Large immutable edits can
exceed one frame; do not claim 60 FPS from these measurements.

### Graph runtime measurement contract

`tool/graph_execution_benchmark_test.dart` records 21 samples after three warmups for linear 100/500/1,000-node, 100-iteration loop and eight-subgraph fixtures. It separates canonical signature construction, cold compilation including its signature, hot cache lookup, VM execution and VM execution with bounded tracing. Reports include program instruction/action/slot/subgraph/wire counts, executed instructions, signature bytes and cache counters. These structural counts are not retained program byte sizes. The authoring benchmark remains a separate gate.

Run from `packages/showrunner-flutter` with Flutter 3.47.7 / Dart 3.13.5:

```powershell
$env:SHOWRUNNER_BENCH_ALLOCATIONS='1'
flutter test --no-pub --enable-vmservice --concurrency=1 tool/graph_execution_benchmark_test.dart
Remove-Item Env:SHOWRUNNER_BENCH_ALLOCATIONS
```

Allocation probes explicitly trace map/list/string classes only during separate untimed operations, then count allocation samples in that operation's VM timeline interval. They are sampled events within a finite VM buffer, not exact total allocations, allocated bytes or retained heap. Large operations can exceed the sample buffer; compare small fixtures and timing distributions without claiming precise memory savings. The probe fails visibly if explicitly requested without a working VM service. The debug service URL is never included in benchmark reports. RPC setup and tracing are outside timed samples. The VM allocation-profile accumulated fields matched current live heap in this environment and produced inconsistent churn deltas; those exploratory values were discarded.

Same Windows machine/SDK, JIT, 21 samples, before/after bounded identity memoization:

| Fixture | Hot lookup before p50/p95 (microseconds) | After p50/p95 (microseconds) |
| --- | --- | --- |
| Linear 100 | 364 / 724 | 7 / 21 |
| Linear 500 | 1,914 / 2,895 | 11 / 15 |
| Linear 1,000 | 4,231 / 5,659 | 14 / 23 |
| Loop 100 | 32 / 52 | 5 / 7 |
| Subgraphs 8 | 84 / 262 | 4 / 7 |

For the 100-node fixture, the selected allocation sample count for one hot lookup fell from 4,885 to 1. The improvement applies to repeated lookup of the same immutable document and entry choice; a new document instance must still build the full signature. VM timings varied between runs and do not establish an execution-speed improvement. No frame-rate or end-to-end latency guarantee follows from this microbenchmark. Raw before/after reports remain ignored under `.tmp/graph-runtime`; reproducible fixtures and this measurement contract are maintained here.

The independent interpreter differential suite adds 30 bounded synthetic seeds, each with completion, cancellation and failure modes. It covers wired variables, branches/switches, for/foreach/while loops, nested subgraph calls/returns, per-action observations and final results. Failures include the seed and synthetic serialized graph; fixtures contain no credentials. Tests also assert that execution leaves the authoring document unchanged.


## External services and release proof

Use [live-services.md](testing/live-services.md) and [live-nodes.md](testing/live-nodes.md)
for credentials, eligibility and previously demonstrated limits. Explicitly distinguish
fixtures, API acceptance and delivered real events. Never auto-enable write scenarios
or print tokens. The [release checklist](release-checklist.md) remains an
operator gate. Public packages and the manual Windows release proof are unsigned;
packaging still exercises installed upgrade/rollback without a signature requirement.
The separate signing-helper fixture uses a temporary test certificate only.
