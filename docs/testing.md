# Testing

Use Flutter 3.47.7 / Dart 3.13.5, Node 22 and Yarn 4.1.0. Install the committed
lockfiles. Tests and smokes must use temporary application data; live settings,
OBS profiles and credentials are never disposable fixtures.

## Baseline and behavior contracts

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
| Shell startup, wizard, dirty/save/cancel, restart and tray/close | `test/app/app_lifecycle_coordinator_test.dart`, `integration_test/application/first_run_setup_test.dart`, `document_lifecycle_test.dart`, `document_edit_save_close_test.dart` | Native OS tray behavior and 1024x640 wizard need explicit size-specific/manual proof |
| Immutable graph authoring, history, subgraphs, shader semantics | `test/graph/`, `test/plugins/overlays/shader_graph_controller_test.dart`, `integration_test/visual/editor_workflows_test.dart`, `shader_workflows_test.dart` | Frozen Electron catalog remains diagnostic |
| Execution equivalence, branches/loops, cancellation, nested errors and traces | `test/graph/automation_execution_test.dart`, `test/runtime/execution_trace_test.dart`, `integration_test/runtime/runtime_workflows_test.dart` | External action side effects require live credentials |
| Queues, profiles and serial Stream Plan transitions | `test/runtime/action_queue_test.dart`, `profile_runtime_test.dart`, `test/plugins/stream_plans/stream_plan_test.dart`, `integration_test/resources/queue_lifecycle_test.dart` | Real provider delivery remains opt-in |
| Plugin availability, start/stop and reconnect | `test/plugins/registry/plugin_registry_test.dart`, `integration_test/plugins/provider_lifecycle_test.dart` | Enable/disable gates invocation; it does not promise worker stop/start on each toggle |
| Unsupported/invalid data, atomic writes, secret separation, junctions | `test/persistence/persistence_safety_test.dart`, `atomic_file_test.dart`, `secret_settings_store_test.dart` | Process termination during an actual disk write is not a demonstrated crash-recovery test |
| Overlay/remote assets, RPC, ACL, shader rendering | `test/plugins/overlays/websocket_bridge_test.dart`, `test/plugins/remote/dashboard_host_test.dart`, `tools/overlay_registry/browser-smoke.mjs` | See architecture trust review for unresolved LAN capabilities and quotas |
| Chat priority/cooldowns/counters, identity scoping and private/public isolation | `test/features/chat/`, `integration_test/application/chat_workspaces_test.dart` | Twitch whispers and YouTube privileges still require account validation |
| Unsigned packaging, startup and updater rollback | `test/features/support/update_install_service_test.dart`, `scripts/smoke-flutter-windows.ps1`, release dry-run | Publishing remains a separate manually authorized operation |

Keep this matrix tied to executable fixtures. Add a missing behavior test before
changing its implementation; do not duplicate an equivalent suite or mark an
untested access path as a confirmed vulnerability. Baseline phase completion also
requires closing the open items in the architecture trust review.

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

## External services and release proof

Use [live-services.md](testing/live-services.md) and [live-nodes.md](testing/live-nodes.md)
for credentials, eligibility and previously demonstrated limits. Explicitly distinguish
fixtures, API acceptance and delivered real events. Never auto-enable write scenarios
or print tokens. The [release checklist](release-checklist.md) remains an
operator gate. Public packages and the manual Windows release proof are unsigned;
packaging still exercises installed upgrade/rollback without a signature requirement.
The separate signing-helper fixture uses a temporary test certificate only.
